/**
 * People matcher — memory layer Phase 1.1 (designs/Atlas Memory Layer build plan).
 *
 * Turns the names and addresses that flow past in signals into contact cards
 * (`people` rows). KEPT DELIBERATELY DUMB on principle (locked decision §4):
 * wrongly merging two Rahuls would make Ayumi confidently wrong about a person —
 * the single worst failure a chief of staff can have. So:
 *
 *   - exact (lowercased) email match against a card's handles → use that card;
 *   - a never-seen email → a NEW card, even if the display name looks familiar;
 *   - a bare name with no email → a temporary name-only card, reused only on an
 *     exact-name match against exactly one other name-only card;
 *   - anything ambiguous (a new address whose display name exactly matches an
 *     existing card, two cards answering to the same name) becomes a merge
 *     SUGGESTION for the operator to approve — never an automatic merge.
 *
 * An approved merge calls `mergePeople`, which points the loser at the winner
 * via `mergedIntoId` and unions handles onto the winner — nothing is deleted,
 * so "Karan exists exactly once, with both his email addresses on one card".
 */
import { randomUUID } from "node:crypto";
import { and, eq, isNull } from "drizzle-orm";
import { db, schema } from "../db";

// ─── address parsing ─────────────────────────────────────────────────

/** One parsed mention of a person: at least one of email / name is present. */
export interface Address {
  /** Lowercased bare address, e.g. "karan@sequoiacap.com". Null for bare names. */
  email: string | null;
  /** Display name as written, e.g. "Karan Mohla". Null when only an address appeared. */
  name: string | null;
}

const EMAIL_RE = /^[^\s@<>,;"']+@[^\s@<>,;"']+\.[^\s@<>,;"']+$/;

/**
 * Bulk/robot senders we don't card (and don't set the desk for). Deliberately
 * narrow — a false skip just means no card until a human-looking mention shows
 * up; a false card is noise in the notebook.
 */
export const ROBOT_RE =
  /^(no-?reply|donotreply|do-not-reply|notifications?|newsletter|news-\d+|mailer-daemon|postmaster|bounce)[@.+-]/i;

/**
 * Parse one RFC822-ish mailbox: `Name <email>`, `<email>`, a bare email, or a
 * bare name. Returns null for empty/no-reply-shaped junk we shouldn't card.
 */
export function parseAddress(raw: string): Address | null {
  const s = raw.trim().replace(/^"|"$/g, "").trim();
  if (!s) return null;
  const angled = s.match(/^(.*?)<\s*([^<>]+?)\s*>$/);
  if (angled) {
    const email = angled[2].trim().toLowerCase();
    const name = angled[1].trim().replace(/^"|"$/g, "").trim() || null;
    if (!EMAIL_RE.test(email)) return name ? { email: null, name } : null;
    return { email, name };
  }
  if (EMAIL_RE.test(s)) return { email: s.toLowerCase(), name: null };
  return { email: null, name: s };
}

/**
 * Split an address-list header (`To: a@b.com, "Mohla, Karan" <k@s.com>`) on
 * commas that sit OUTSIDE quotes and angle brackets, then parse each mailbox.
 */
export function parseAddressList(raw: string): Address[] {
  const parts: string[] = [];
  let buf = "";
  let inQuotes = false;
  let inAngle = false;
  for (const ch of raw) {
    if (ch === '"') inQuotes = !inQuotes;
    else if (ch === "<" && !inQuotes) inAngle = true;
    else if (ch === ">" && !inQuotes) inAngle = false;
    if (ch === "," && !inQuotes && !inAngle) {
      parts.push(buf);
      buf = "";
    } else {
      buf += ch;
    }
  }
  parts.push(buf);
  return parts.map(parseAddress).filter((a): a is Address => a !== null);
}

/**
 * Pull every person-mention out of one signal's rawData, per source. Handles
 * both the demo/fixture shapes and the real-connector shapes:
 *   gmail    — `from` (bare email or `Name <email>`), `to` / `cc` (lists)
 *   calendar — `attendees` (array of email strings; iOS EventKit pushes carry
 *              none, the Google path always sends bare emails)
 *   drive    — no author data in today's rawData shape; nothing to extract
 */
export function extractAddresses(signal: schema.Signal): Address[] {
  const raw = signal.rawData as Record<string, unknown>;
  const out: Address[] = [];
  if (signal.source === "gmail") {
    if (typeof raw.from === "string" && raw.from) {
      const a = parseAddress(raw.from);
      if (a) out.push(a);
    }
    for (const field of ["to", "cc"]) {
      const v = raw[field];
      if (typeof v === "string" && v) out.push(...parseAddressList(v));
    }
  } else if (signal.source === "calendar") {
    const attendees = raw.attendees;
    if (Array.isArray(attendees)) {
      for (const a of attendees) {
        if (typeof a === "string" && a) {
          const parsed = parseAddress(a);
          if (parsed) out.push(parsed);
        }
      }
    }
  }
  return out;
}

// ─── matching ────────────────────────────────────────────────────────

/** A merge the matcher noticed but refused to perform — operator's call. */
export interface MergeSuggestion {
  /** Why these look like one person, in plain words (for script output / a future screen). */
  reason: string;
  personIds: string[];
}

export interface ResolveResult {
  person: schema.Person;
  created: boolean;
  suggestion: MergeSuggestion | null;
}

const norm = (s: string) => s.trim().toLowerCase();

/** Live (non-deleted) cards for a user. Small table; whole-scan is fine at our scale. */
function livePeople(userId: string): schema.Person[] {
  return db
    .select()
    .from(schema.people)
    .where(and(eq(schema.people.userId, userId), isNull(schema.people.deletedAt)))
    .all();
}

/** Follow `mergedIntoId` pointers to the surviving card (bounded — no cycles by construction). */
export function followMerges(person: schema.Person, all?: schema.Person[]): schema.Person {
  const cards = all ?? livePeople(person.userId);
  let cur = person;
  for (let hops = 0; cur.mergedIntoId && hops < 10; hops++) {
    const next = cards.find((p) => p.id === cur.mergedIntoId);
    if (!next) break;
    cur = next;
  }
  return cur;
}

/**
 * Resolve one parsed address to a contact card, creating one if needed.
 * `seenAt` stamps firstSeen/lastSeen (the signal's arrivedAt, not "now", so a
 * backfill over old mail builds an honest timeline).
 */
export function resolvePerson(
  userId: string,
  address: Address,
  seenAt: string,
): ResolveResult {
  const cards = livePeople(userId);
  const nowIso = new Date().toISOString();

  // 1 · Exact email match — the only automatic identification we trust.
  if (address.email) {
    const matches = cards.filter((p) =>
      (p.handles ?? []).some((h) => norm(h) === address.email),
    );
    if (matches.length > 0) {
      // Same address on several cards should be impossible (we always match
      // before creating) — if it ever happens, use the oldest and SAY SO.
      const card = followMerges(
        matches.slice().sort((a, b) => a.createdAt.localeCompare(b.createdAt))[0],
        cards,
      );
      touchCard(card, address, seenAt, nowIso);
      return {
        person: card,
        created: false,
        suggestion:
          matches.length > 1
            ? {
                reason: `address ${address.email} appears on ${matches.length} cards`,
                personIds: matches.map((m) => m.id),
              }
            : null,
      };
    }

    // New address → new card. If the display name exactly matches an existing
    // card, that is the classic "second address" situation — suggest, don't merge.
    const handles = [address.email];
    if (address.name && norm(address.name) !== address.email) handles.push(address.name);
    const card: schema.NewPerson = {
      id: randomUUID(),
      userId,
      canonicalName: address.name ?? address.email.split("@")[0],
      handles,
      firstSeenAt: seenAt,
      lastSeenAt: seenAt,
      updatedAt: nowIso,
    };
    db.insert(schema.people).values(card).run();
    const inserted = db
      .select()
      .from(schema.people)
      .where(eq(schema.people.id, card.id as string))
      .get()!;

    let suggestion: MergeSuggestion | null = null;
    if (address.name) {
      const sameName = cards.filter((p) => norm(p.canonicalName) === norm(address.name!));
      if (sameName.length > 0) {
        suggestion = {
          reason: `"${address.name}" already has a card — is ${address.email} a second address for the same person?`,
          personIds: [inserted.id, ...sameName.map((p) => p.id)],
        };
      }
    }
    return { person: inserted, created: true, suggestion };
  }

  // 2 · Bare name, no email → temporary name-only card. Reuse only an exact
  // name match against exactly one other NAME-ONLY card; matching a bare name
  // onto an email-bearing card is exactly the merge we refuse to guess at.
  const name = address.name!;
  const nameOnly = cards.filter(
    (p) =>
      norm(p.canonicalName) === norm(name) &&
      !(p.handles ?? []).some((h) => EMAIL_RE.test(h)),
  );
  if (nameOnly.length === 1) {
    const card = followMerges(nameOnly[0], cards);
    touchCard(card, address, seenAt, nowIso);
    return { person: card, created: false, suggestion: null };
  }
  if (nameOnly.length > 1) {
    // Two temp cards with the same name — already ambiguous; reuse the oldest
    // and surface the mess rather than minting a third.
    const card = nameOnly.slice().sort((a, b) => a.createdAt.localeCompare(b.createdAt))[0];
    touchCard(card, address, seenAt, nowIso);
    return {
      person: card,
      created: false,
      suggestion: {
        reason: `${nameOnly.length} name-only cards answer to "${name}"`,
        personIds: nameOnly.map((p) => p.id),
      },
    };
  }

  const emailCardsSameName = cards.filter((p) => norm(p.canonicalName) === norm(name));
  const card: schema.NewPerson = {
    id: randomUUID(),
    userId,
    canonicalName: name,
    handles: [name],
    firstSeenAt: seenAt,
    lastSeenAt: seenAt,
    updatedAt: nowIso,
  };
  db.insert(schema.people).values(card).run();
  const inserted = db
    .select()
    .from(schema.people)
    .where(eq(schema.people.id, card.id as string))
    .get()!;
  return {
    person: inserted,
    created: true,
    suggestion:
      emailCardsSameName.length > 0
        ? {
            reason: `bare mention "${name}" might be the carded ${emailCardsSameName
              .map((p) => `${p.canonicalName} <${(p.handles ?? []).find((h) => EMAIL_RE.test(h)) ?? "?"}>`)
              .join(" / ")} — approve to merge`,
            personIds: [inserted.id, ...emailCardsSameName.map((p) => p.id)],
          }
        : null,
  };
}

/** Bump lastSeenAt (and firstSeenAt backwards, for backfills over old mail) + learn a new display-name handle. */
function touchCard(card: schema.Person, address: Address, seenAt: string, nowIso: string): void {
  const handles = [...(card.handles ?? [])];
  let changed = false;
  if (address.name && !handles.some((h) => norm(h) === norm(address.name!))) {
    handles.push(address.name);
    changed = true;
  }
  const first = seenAt < card.firstSeenAt ? seenAt : card.firstSeenAt;
  const last = seenAt > card.lastSeenAt ? seenAt : card.lastSeenAt;
  if (!changed && first === card.firstSeenAt && last === card.lastSeenAt) return;
  db.update(schema.people)
    .set({ handles, firstSeenAt: first, lastSeenAt: last, updatedAt: nowIso })
    .where(eq(schema.people.id, card.id))
    .run();
  card.handles = handles;
  card.firstSeenAt = first;
  card.lastSeenAt = last;
}

/**
 * The OPERATOR-APPROVED merge (never called automatically): point `loserId` at
 * `winnerId` and union the loser's handles onto the winner, so the surviving
 * card carries both addresses. The loser's row stays — don't delete.
 */
export function mergePeople(userId: string, loserId: string, winnerId: string): schema.Person {
  const cards = livePeople(userId);
  const loser = cards.find((p) => p.id === loserId);
  const winner = cards.find((p) => p.id === winnerId);
  if (!loser || !winner) throw new Error(`mergePeople: unknown card ${!loser ? loserId : winnerId}`);
  if (loser.id === winner.id) throw new Error("mergePeople: cannot merge a card into itself");

  const nowIso = new Date().toISOString();
  const handles = [...(winner.handles ?? [])];
  for (const h of loser.handles ?? []) {
    if (!handles.some((x) => norm(x) === norm(h))) handles.push(h);
  }
  const first = loser.firstSeenAt < winner.firstSeenAt ? loser.firstSeenAt : winner.firstSeenAt;
  const last = loser.lastSeenAt > winner.lastSeenAt ? loser.lastSeenAt : winner.lastSeenAt;

  db.update(schema.people)
    .set({ mergedIntoId: winner.id, updatedAt: nowIso })
    .where(eq(schema.people.id, loser.id))
    .run();
  db.update(schema.people)
    .set({ handles, firstSeenAt: first, lastSeenAt: last, updatedAt: nowIso })
    .where(eq(schema.people.id, winner.id))
    .run();
  return db.select().from(schema.people).where(eq(schema.people.id, winner.id)).get()!;
}

/**
 * Find the card a free-text query refers to (used by `person_lookup` and the
 * read path). Email queries match handles exactly; name queries match
 * canonicalName or a name handle, case-insensitively. Follows merge pointers.
 */
export function findPerson(userId: string, query: string): schema.Person | null {
  const q = norm(query);
  if (!q) return null;
  const cards = livePeople(userId);
  const hit = cards.find(
    (p) =>
      norm(p.canonicalName) === q ||
      (p.handles ?? []).some((h) => norm(h) === q) ||
      norm(p.canonicalName).includes(q),
  );
  return hit ? followMerges(hit, cards) : null;
}
