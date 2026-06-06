/**
 * Backfill people — memory layer Phase 1.2 (designs/Atlas Memory Layer build plan).
 *
 * One pass over the emails and calendar events already in the database —
 * sender, recipients, attendees — so the contact cards start populated.
 * Idempotent: the matcher resolves by exact email first, so a second run
 * creates zero new cards.
 *
 *   pnpm tsx scripts/backfill-people.ts
 *   pnpm tsx scripts/backfill-people.ts --merge <loserId> <winnerId>
 *
 * The --merge form is the operator's approval for a printed suggestion: it
 * points the loser card at the winner (`mergedIntoId`) and unions handles, so
 * the surviving card carries both addresses. Never run automatically.
 */
import { inArray, isNull, and } from "drizzle-orm";
import { db, schema } from "../worker/src/db";
import {
  extractAddresses,
  resolvePerson,
  mergePeople,
  ROBOT_RE,
  type MergeSuggestion,
} from "../worker/src/memory/people";

function main(): void {
  const [, , flag, a, b] = process.argv;
  if (flag === "--merge") {
    if (!a || !b) {
      console.error("usage: tsx scripts/backfill-people.ts --merge <loserId> <winnerId>");
      process.exit(1);
    }
    const winner = mergePeople(schema.BOOTSTRAP_USER_ID, a, b);
    console.log(
      `[people] merged ${a} → ${winner.id} · "${winner.canonicalName}" now carries: ${(winner.handles ?? []).join(", ")}`,
    );
    return;
  }

  const signals = db
    .select()
    .from(schema.signals)
    .where(
      and(
        inArray(schema.signals.source, ["gmail", "calendar"]),
        isNull(schema.signals.deletedAt),
      ),
    )
    .all();

  let created = 0;
  let reused = 0;
  let robots = 0;
  const suggestions: MergeSuggestion[] = [];
  const seenSuggestion = new Set<string>();

  for (const signal of signals) {
    for (const address of extractAddresses(signal)) {
      if (address.email && ROBOT_RE.test(address.email)) {
        robots++;
        continue;
      }
      const res = resolvePerson(signal.userId, address, signal.arrivedAt);
      if (res.created) {
        created++;
        console.log(
          `[people] + ${res.person.canonicalName} (${(res.person.handles ?? []).join(", ")})`,
        );
      } else {
        reused++;
      }
      if (res.suggestion) {
        const key = res.suggestion.personIds.slice().sort().join("|");
        if (!seenSuggestion.has(key)) {
          seenSuggestion.add(key);
          suggestions.push(res.suggestion);
        }
      }
    }
  }

  const totalCards = db
    .select({ id: schema.people.id })
    .from(schema.people)
    .where(isNull(schema.people.deletedAt))
    .all().length;

  console.log(
    `[people] backfill done — ${signals.length} signals · ${created} cards created · ${reused} mentions matched existing cards · ${robots} robot addresses skipped · ${totalCards} cards total`,
  );

  if (suggestions.length > 0) {
    console.log(`\n[people] ${suggestions.length} merge suggestion(s) — approve with --merge <loserId> <winnerId>:`);
    for (const s of suggestions) {
      console.log(`  · ${s.reason}`);
      console.log(`    cards: ${s.personIds.join("  ")}`);
    }
  }
}

main();
