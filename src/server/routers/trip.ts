import { z } from "zod";
import { and, eq } from "drizzle-orm";
import { randomUUID } from "node:crypto";
import { router, protectedProcedure } from "../trpc";
import { db } from "@/db/client";
import { tripState, tripPreferences } from "@/db/schema";

/**
 * Trip router (v0.7 — the Living Chapter).
 *
 * Backs the North India chapter detail (design handoff PART 2): a chapter Ayumi
 * inferred from *one* flight email and now tracks live. The shape mirrors the
 * README STATE MODEL (`chapter.{ stops, legs, spend, recommendations, tracking,
 * connectors, receipts }`), with every fact carrying provenance
 * (`booked` | `inferred` | `live`) so the UI can render the chip on each fact.
 *
 *  - `get({ id })` → Trip-shaped JSON. A fixed seed renders the chapter OFFLINE;
 *    the caller's persisted overlay (`trip_state`) + learned preferences
 *    (`trip_preferences`) are applied on top so their reconciles + connector
 *    grants survive across reads and visibly tune the NEXT suggestion.
 *  - `correct({ targetId, answer })` → `{ patch, ripple:{changed}, learned }`
 *    "no, I took the bus": a real mutation + deterministic recompute over the
 *    trip model — rewrite the leg (mode+fare), rebalance `spend.total` + segment
 *    breakdown, PERSIST a learned preference so the next render leads differently.
 *  - `grantConnector({ id })` → `{ status, role, unlockCopy, needsRederive }`
 *    Consent for a source (HDFC / IRCTC / Calendar): flip available→feeding,
 *    rewrite what she can now do, and mark the chapter for re-derivation.
 *
 * All procedures are `protectedProcedure` + Zod-validated + scoped to
 * `ctx.userId`; persisted state lives in SQLite (`trip_state`,
 * `trip_preferences`). The trip *base* is a seed (illustrative demo content per
 * README "A note on scope of the demo data"); the corrections, grants, and
 * learned preferences are durable per-user data.
 */

// ─────────────────────────── Trip shape (README STATE MODEL) ───────────────────────────

const provenanceEnum = z.enum(["booked", "inferred", "live"]);
const stopStateEnum = z.enum(["done", "here", "upcoming"]);
const connectorStatusEnum = z.enum(["feeding", "available"]);

const Stop = z.object({
  id: z.string(),
  place: z.string(),
  dates: z.string(),
  note: z.string(),
  /** Single-line italic summary shown when a past stop is collapsed. */
  mini: z.string(),
  state: stopStateEnum,
  provenance: z.array(provenanceEnum),
  /** Past stops render collapsed; current/upcoming stay open. */
  collapsed: z.boolean(),
});

const Leg = z.object({
  id: z.string(),
  /** From/To stop ids the leg joins (ground transport between stops). */
  fromStop: z.string(),
  toStop: z.string(),
  mode: z.string(),
  /** Ayumi's reasoning line ("overnight like your Manali run — saved a day"). */
  why: z.string(),
  fare: z.string(),
  booked: z.boolean(),
  /** A persistent "updated by you" trace once the user has corrected this leg. */
  correctedByUser: z.boolean(),
});

const SpendSegment = z.object({
  key: z.enum(["flights", "stays", "food", "travel"]),
  label: z.string(),
  amount: z.number(),
});

const Spend = z.object({
  total: z.number(),
  projected: z.number(),
  currency: z.string(),
  segments: z.array(SpendSegment),
  /** Where each number came from + what is deliberately not counted yet. */
  sources: z.array(z.string()),
});

const Recommendation = z.object({
  id: z.string(),
  title: z.string(),
  blurb: z.string(),
  /** The taste signal that justifies the rec ("you rate specialty coffee…"). */
  signal: z.string(),
});

const TrackingStat = z.object({
  id: z.string(),
  label: z.string(),
  value: z.string(),
  detail: z.string(),
  source: z.string(),
});

const Connector = z.object({
  id: z.string(),
  name: z.string(),
  /** One-line statement of the source's role / what granting it unlocks. */
  role: z.string(),
  status: connectorStatusEnum,
  unlockCopy: z.string(),
});

const Receipt = z.object({
  id: z.string(),
  label: z.string(),
  /** The exact sources behind this step of the chain (email → inference → live). */
  sources: z.array(z.string()),
});

const Trip = z.object({
  id: z.string(),
  title: z.string(),
  framing: z.string(),
  dateRange: z.string(),
  meta: z.string(),
  stops: z.array(Stop),
  legs: z.array(Leg),
  spend: Spend,
  recommendations: z.array(Recommendation),
  tracking: z.array(TrackingStat),
  connectors: z.array(Connector),
  receipts: z.array(Receipt),
});

type Trip = z.infer<typeof Trip>;
type Leg = z.infer<typeof Leg>;
type SpendSegment = z.infer<typeof SpendSegment>;
type Connector = z.infer<typeof Connector>;

// ─────────────────────────── Seed: North India (day 5, Rishikesh) ───────────────────────────
//
// The fixed base the chapter renders from offline. Only `legs`, `spend`, and
// `connectors` are mutated by corrections/grants — the rest is constant.

// ─────────────────────────────────────────────────────────────────────────────
// The shared, visible facts below are BYTE-ALIGNED with the iOS seed
// (ios/Atlas/Agent/AtlasRepo.swift · NorthIndiaSeed) for every field `mergeTrip`
// overwrites — title, framing, dateRange, meta, stop dates/notes/minis/
// provenance, leg modes/why/fares, spend total+segments+sources, recommendation
// copy, tracking values, connector roles. So the chapter does NOT visibly change
// the instant the server (`.server`) path turns on. Keep the two in lockstep.
// ─────────────────────────────────────────────────────────────────────────────
const SEED: Trip = {
  id: "north",
  // iOS renders "<title>." — keep the period off here (mergeTrip strips it anyway).
  title: "North India",
  framing:
    "You gave me one flight confirmation. From that, I built the whole trip — and I’m still watching it unfold.",
  dateRange: "18–30 May · 5 stops · day 5",
  meta: "built from 1 email · watching 4 sources",
  stops: [
    {
      id: "delhi",
      place: "Delhi",
      dates: "18–19 May",
      note: "Landed IndiGo 6E-2043, overnight near the airport before heading up to the hills.",
      mini: "Landed, one night near the airport.",
      state: "done",
      provenance: ["booked"],
      collapsed: true,
    },
    {
      id: "nainital",
      place: "Nainital",
      dates: "19–22 May",
      note: "Three nights by the lake. Boating at Naini, the Mall Road evenings, a day up to Tiffin Top.",
      mini: "Three nights by the lake.",
      state: "done",
      provenance: ["inferred", "live"],
      collapsed: true,
    },
    {
      id: "rishikesh",
      place: "Rishikesh",
      dates: "22–27 May",
      note: "The reason for the trip. Ganga aarti at Triveni Ghat, a morning at the Beatles Ashram, and the river itself. You’re here now, on day 5.",
      mini: "Day 5 — you’re here.",
      state: "here",
      provenance: ["live"],
      collapsed: false,
    },
    {
      id: "kasol",
      place: "Kasol",
      dates: "27–29 May",
      note: "I added this — you searched “Kheerganga trek” twice in April. Two nights in Parvati Valley, the obvious base for the trek.",
      mini: "Inferred from your searches.",
      state: "upcoming",
      provenance: ["inferred"],
      collapsed: false,
    },
    {
      id: "chandigarh",
      place: "Chandigarh",
      dates: "29–30 May",
      note: "Out the same way you’ll fly home — IndiGo 6E-185, Chandigarh → Delhi → home.",
      mini: "Fly home from here.",
      state: "upcoming",
      provenance: ["booked"],
      collapsed: false,
    },
  ],
  legs: [
    {
      id: "leg-nainital",
      fromStop: "delhi",
      toStop: "nainital",
      // Deliberately seeded WRONG so the correction has something real to fix.
      mode: "Flew to Pantnagar",
      why: "Quickest hop off the plains — a short flight, then the climb up.",
      fare: "₹4,900",
      booked: true,
      correctedByUser: false,
    },
    {
      id: "leg-rishikesh",
      fromStop: "nainital",
      toStop: "rishikesh",
      mode: "Drove down via Kathgodam",
      why: "Overnight like your Manali run — saved a day on the road.",
      fare: "₹3,200",
      booked: true,
      correctedByUser: false,
    },
    {
      id: "leg-kasol",
      fromStop: "rishikesh",
      toStop: "kasol",
      mode: "Overnight to Bhuntar, cab to Kasol",
      why: "You get carsick on switchbacks — I’d split it overnight at Bhuntar, then a short cab in.",
      fare: "",
      booked: false,
      correctedByUser: false,
    },
    {
      id: "leg-chandigarh",
      fromStop: "kasol",
      toStop: "chandigarh",
      mode: "Volvo to Chandigarh",
      why: "Lines up with your morning flight — leaves you a buffer at the airport.",
      fare: "",
      booked: false,
      correctedByUser: false,
    },
  ],
  spend: {
    total: 34_750,
    projected: 68_000,
    currency: "₹",
    // Byte-aligned with the iOS seed's segment split (sums to total 34,750).
    segments: [
      { key: "flights", label: "Flights", amount: 12_400 },
      { key: "stays", label: "Stays", amount: 13_900 },
      { key: "food", label: "Food", amount: 5_650 },
      { key: "travel", label: "Travel", amount: 2_800 },
    ],
    sources: [
      "Bookings (flights, stays) read from your inbox. Food from your card-swipe SMS.",
      "The two unbooked legs — Rishikesh → Kasol and Kasol → Chandigarh — aren’t counted yet.",
    ],
  },
  // Recommendation copy aligned with the iOS seed (mergeTrip overwrites
  // title→text + signal→tasteSignal; iOS owns the thumb gradient + place label).
  recommendations: [
    {
      id: "bluetokai",
      title: "Blue Tokai",
      blurb: "Single-origin pour-over a five-minute walk from your stay.",
      signal:
        "you rate specialty coffee everywhere — Blue Tokai is your most-visited place back home.",
    },
    {
      id: "kheerganga",
      title: "Kheerganga trek",
      blurb: "Hot springs at the top, doable from Kasol in a day.",
      signal:
        "matches the trek you searched twice in April — the hot springs at the top are the payoff.",
    },
  ],
  // Tracking values aligned with the iOS seed (mergeTrip overwrites value + detail;
  // iOS owns the dots / sparkline / wide layout).
  tracking: [
    {
      id: "places",
      label: "Places visited",
      value: "2",
      detail: "Delhi · Nainital · here",
      source: "Maps timeline",
    },
    {
      id: "steps",
      label: "Today's steps",
      value: "11.4k",
      detail: "Apple Health",
      source: "Apple Health",
    },
    {
      id: "totals",
      label: "Trip totals",
      value: "58k",
      detail: "1,240m climbed · 5 days · Health + Maps",
      source: "Apple Health",
    },
  ],
  // Connector roles aligned with the iOS seed (mergeTrip overwrites name + role +
  // status + unlockCopy; iOS owns the icon swatch). grantCopyFor() rewrites the
  // role on grant — see grantedRole parity in the iOS seed.
  connectors: [
    {
      id: "gmail",
      name: "Gmail",
      role: "Reading bookings — your flights and stays.",
      status: "feeding",
      unlockCopy: "",
    },
    {
      id: "health",
      name: "Apple Health",
      role: "Counting steps and the climb up the hills.",
      status: "feeding",
      unlockCopy: "",
    },
    {
      id: "maps",
      name: "Maps",
      role: "Confirming where you actually are — Rishikesh, day 5.",
      status: "feeding",
      unlockCopy: "",
    },
    {
      id: "hdfc",
      name: "HDFC card",
      role: "Where your money’s going on the ground.",
      status: "available",
      unlockCopy: "I’d read your card swipes — exact food + travel spend, not an estimate.",
    },
    {
      id: "irctc",
      name: "IRCTC rail",
      role: "Live trains for the legs I haven’t booked.",
      status: "available",
      unlockCopy: "I’d hold real sleeper berths for the Kasol leg instead of guessing.",
    },
    {
      id: "calendar",
      name: "Calendar",
      role: "What’s waiting for you back home.",
      status: "available",
      unlockCopy:
        "I’d work the trip around your first day back — and warn you about the clash on the 31st.",
    },
  ],
  receipts: [
    {
      id: "rcpt-email",
      label: "The one email",
      sources: ["Gmail · flight confirmation · Delhi in / Chandigarh out"],
    },
    {
      id: "rcpt-inference",
      label: "The inferred itinerary",
      sources: ["Search history · Kheerganga trek ×2", "Your past trips · Manali overnight pattern"],
    },
    {
      id: "rcpt-live",
      label: "Confirmed live",
      sources: ["Maps timeline · Delhi, Nainital", "Apple Health · steps & climb"],
    },
  ],
};

/** Registry of seeded trips, by id. (North India is the only chapter for v0.7.) */
const SEEDS: Record<string, Trip> = { north: SEED };

// ─────────────────────────── deterministic money helpers ───────────────────────────

/** "₹4,900" → 4900 ; "from ₹1,400" → 1400 ; "" / unbooked → 0. */
function parseFare(fare: string): number {
  const m = fare.replace(/[, ]/g, "").match(/(\d+)/);
  return m ? Number(m[1]) : 0;
}

/** 4900 → "₹4,900". */
function formatFare(n: number): string {
  return "₹" + n.toLocaleString("en-IN");
}

// ─────────────────────────── correction model (deterministic reconcile) ───────────────────────────

/**
 * The reconcile rules, keyed by the leg being corrected. Each maps a chosen
 * answer (a quick-answer chip or free text matched to one) to the *new* leg facts
 * and the spend deltas — so `applyCorrection` can recompute the total + segments
 * deterministically from the base seed regardless of which patches are applied.
 *
 * `delta.travel` etc. are signed rupee adjustments to a segment. The "flight that
 * wasn't" case moves money out of `flights` and into `travel`, dropping the total.
 */
interface CorrectionRule {
  /** New leg mode label after reconcile. */
  mode: string;
  /** New leg fare (rupees); folded into the segment recompute. */
  fareRupees: number;
  /** Now a confirmed actual, not an inference. */
  booked: boolean;
  /** Signed segment adjustments applied on top of the base segment amounts. */
  segmentDelta: Partial<Record<SpendSegment["key"], number>>;
  /** The "what I learned" line + the durable preference it writes. */
  learned: string;
  prefKey: string;
  prefValue: string;
  /** How the ripple toast states the change (excluding the learned line). */
  changed: (newTotal: number) => string;
}

/**
 * Match a free-text / chip answer to a reconcile rule for the Delhi→Nainital leg.
 * The README seeds three quick-answer chips (Overnight Volvo bus / Shared cab /
 * Train via Kathgodam); free text falls through to the bus case (the demo's
 * canonical "no, I took the bus").
 */
function ruleForNainital(answer: string): CorrectionRule {
  const a = answer.toLowerCase();
  // The seeded base has the wrong leg in `flights` at ₹4,900; every real ground
  // option pulls that out of flights and books a smaller travel fare instead.
  if (a.includes("cab") || a.includes("taxi") || a.includes("car")) {
    return {
      mode: "Shared cab via Kathgodam",
      fareRupees: 2_400,
      booked: true,
      segmentDelta: { flights: -4_900, travel: +2_400 },
      learned: "You'd rather drive the first leg than fly it — I'll price cabs first up here.",
      prefKey: "ground_transport",
      prefValue: "shared_cab",
      changed: (t) => `Nainital leg is a shared cab now, not a flight — spend is ${formatFare(t)}.`,
    };
  }
  if (a.includes("train") || a.includes("rail") || a.includes("kathgodam")) {
    return {
      mode: "Train to Kathgodam, cab up",
      fareRupees: 1_450,
      booked: true,
      segmentDelta: { flights: -4_900, travel: +1_450 },
      learned: "You took the train, not the flight — I'll lead with rail on legs like this.",
      prefKey: "ground_transport",
      prefValue: "train",
      changed: (t) => `Nainital leg is the Kathgodam train now, not a flight — spend is ${formatFare(t)}.`,
    };
  }
  // Default + explicit bus/Volvo: the canonical "no, I took the bus".
  return {
    mode: "Overnight Volvo bus",
    fareRupees: 1_150,
    booked: true,
    segmentDelta: { flights: -4_900, travel: +1_150 },
    learned: "You chose the bus over the flight — I'll lead with sleepers on your Kasol leg too.",
    prefKey: "ground_transport",
    prefValue: "sleeper_bus",
    changed: (t) => `Nainital leg is an overnight bus now, not a flight — spend dropped to ${formatFare(t)}.`,
  };
}

/** Resolve the reconcile rule for any corrected leg. */
function ruleFor(legId: string, answer: string): CorrectionRule | null {
  if (legId === "leg-nainital") return ruleForNainital(answer);
  // Other past legs reconcile generically against the answer (no scripted spend
  // shift — we just record the user's correction + a soft preference).
  return null;
}

// ─────────────────────────── overlay persistence types ───────────────────────────

interface LegPatch {
  mode: string;
  fare: string;
  fareRupees: number;
  booked: boolean;
  correctedByUser: true;
  /** The segment deltas this patch contributed (so spend recomputes from base). */
  segmentDelta: Partial<Record<SpendSegment["key"], number>>;
}

interface ConnectorGrant {
  status: "feeding";
  role: string;
  unlockCopy: string;
  grantedAt: string;
}

/** Rewritten copy applied to a connector the moment it's granted. */
function grantCopyFor(c: Connector): { role: string; unlockCopy: string } {
  switch (c.id) {
    case "hdfc":
      return {
        role: "Itemising food and local spend from card-swipe SMS.",
        unlockCopy: "Linked — every swipe lands here, so food is itemised, not estimated.",
      };
    case "irctc":
      return {
        role: "Watching sleeper seats on the Kasol leg.",
        unlockCopy: "Linked — I'll hold a sleeper the moment one opens on the Kasol leg.",
      };
    case "calendar":
      return {
        role: "Planning the return around your week back.",
        unlockCopy: "Linked — I'll plan the way home around your Monday back at work.",
      };
    default:
      return {
        role: "Feeding the chapter now.",
        unlockCopy: `Linked — ${c.name} is feeding the chapter now.`,
      };
  }
}

// ─────────────────────────── overlay → rendered trip ───────────────────────────

interface Overlay {
  legPatches: Record<string, LegPatch>;
  connectorGrants: Record<string, ConnectorGrant>;
  needsRederive: boolean;
}

/** The learned-preference summary `get()` uses to retune the next suggestion. */
interface LearnedPrefs {
  groundTransport?: string;
}

/**
 * Deterministically derive the rendered trip from the fixed seed + the caller's
 * persisted overlay + their learned preferences. Pure: same inputs → same output,
 * so the offline seed and the live read agree until the user changes something.
 */
function deriveTrip(seed: Trip, overlay: Overlay, prefs: LearnedPrefs): Trip {
  // Deep-ish clone of the mutable sections (legs/spend/connectors); the rest is
  // shared by reference (never mutated).
  const legs: Leg[] = seed.legs.map((leg) => {
    const patch = overlay.legPatches[leg.id];
    if (!patch) return { ...leg };
    return {
      ...leg,
      mode: patch.mode,
      fare: patch.fare,
      booked: patch.booked,
      correctedByUser: true,
    };
  });

  // Recompute spend from the base segments + every applied patch's delta, so the
  // total is correct no matter how many legs were corrected (and in any order).
  const segments: SpendSegment[] = seed.spend.segments.map((s) => ({ ...s }));
  for (const patch of Object.values(overlay.legPatches)) {
    for (const seg of segments) {
      const d = patch.segmentDelta[seg.key];
      if (d) seg.amount += d;
    }
  }
  const total = segments.reduce((sum, s) => sum + s.amount, 0);

  const connectors: Connector[] = seed.connectors.map((c) => {
    const grant = overlay.connectorGrants[c.id];
    if (!grant) return { ...c };
    return { ...c, status: "feeding", role: grant.role, unlockCopy: grant.unlockCopy };
  });

  // The point of the reconcile: a learned ground-transport preference rewrites the
  // UNBOOKED suggestion legs' copy so the next render visibly leads differently.
  if (prefs.groundTransport) {
    const kasol = legs.find((l) => l.id === "leg-kasol" && !l.booked && !l.correctedByUser);
    if (kasol) {
      const tuned = tunedSuggestion(prefs.groundTransport);
      if (tuned) {
        kasol.mode = tuned.mode;
        kasol.why = tuned.why;
      }
    }
  }

  return {
    ...seed,
    legs,
    connectors,
    spend: { ...seed.spend, segments, total },
  };
}

/** Map a learned ground-transport preference to retuned Kasol-leg suggestion copy. */
function tunedSuggestion(pref: string): { mode: string; why: string } | null {
  switch (pref) {
    case "sleeper_bus":
      return {
        mode: "Suggest: overnight sleeper bus to Bhuntar",
        why: "You took the bus on the Nainital leg — leading with a sleeper here too, split overnight at Bhuntar.",
      };
    case "train":
      return {
        mode: "Suggest: rail to Bhuntar, cab to Kasol",
        why: "You went by rail earlier — I'll price the train first, then a short cab in from Bhuntar.",
      };
    case "shared_cab":
      return {
        mode: "Suggest: shared cab the whole way",
        why: "You'd rather drive than fly — pricing a shared cab straight through to Kasol.",
      };
    default:
      return null;
  }
}

// ─────────────────────────── overlay loaders (user-scoped) ───────────────────────────

const EMPTY_OVERLAY: Overlay = { legPatches: {}, connectorGrants: {}, needsRederive: false };

function loadOverlay(userId: string, tripId: string): Overlay {
  const row = db
    .select({
      legPatches: tripState.legPatches,
      connectorGrants: tripState.connectorGrants,
      needsRederive: tripState.needsRederive,
    })
    .from(tripState)
    .where(and(eq(tripState.userId, userId), eq(tripState.tripId, tripId)))
    .get();
  if (!row) return EMPTY_OVERLAY;
  return {
    legPatches: (row.legPatches ?? {}) as Record<string, LegPatch>,
    connectorGrants: (row.connectorGrants ?? {}) as Record<string, ConnectorGrant>,
    needsRederive: row.needsRederive ?? false,
  };
}

function loadPrefs(userId: string, tripId: string): LearnedPrefs {
  const rows = db
    .select({ prefKey: tripPreferences.prefKey, prefValue: tripPreferences.prefValue })
    .from(tripPreferences)
    .where(and(eq(tripPreferences.userId, userId), eq(tripPreferences.tripId, tripId)))
    .all();
  const prefs: LearnedPrefs = {};
  for (const r of rows) {
    if (r.prefKey === "ground_transport") prefs.groundTransport = r.prefValue;
  }
  return prefs;
}

/** Upsert the per-(user,trip) overlay, merging the given mutation in. */
function writeOverlay(
  userId: string,
  tripId: string,
  mutate: (o: Overlay) => Overlay,
): Overlay {
  const now = new Date().toISOString();
  const current = loadOverlay(userId, tripId);
  const next = mutate(current);
  const existing = db
    .select({ id: tripState.id })
    .from(tripState)
    .where(and(eq(tripState.userId, userId), eq(tripState.tripId, tripId)))
    .get();
  if (existing) {
    db.update(tripState)
      .set({
        legPatches: next.legPatches,
        connectorGrants: next.connectorGrants,
        needsRederive: next.needsRederive,
        updatedAt: now,
      })
      .where(eq(tripState.id, existing.id))
      .run();
  } else {
    db.insert(tripState)
      .values({
        id: randomUUID(),
        userId,
        tripId,
        legPatches: next.legPatches,
        connectorGrants: next.connectorGrants,
        needsRederive: next.needsRederive,
        updatedAt: now,
      })
      .run();
  }
  return next;
}

// ─────────────────────────── router ───────────────────────────

export const tripRouter = router({
  /**
   * Get a Trip-shaped chapter. Renders the fixed seed (offline) with the caller's
   * persisted overlay (corrections + connector grants) and learned preferences
   * applied on top. Returns null for an unknown id.
   */
  get: protectedProcedure
    .input(z.object({ id: z.string() }))
    .query(({ input, ctx }): Trip | null => {
      const seed = SEEDS[input.id];
      if (!seed) return null;
      const overlay = loadOverlay(ctx.userId, input.id);
      const prefs = loadPrefs(ctx.userId, input.id);
      return deriveTrip(seed, overlay, prefs);
    }),

  /**
   * Reconcile a correction ("no, I took the bus").
   *
   * A real mutation + deterministic recompute over the trip model: validate the
   * target leg, rewrite it (mode + fare + booked), rebalance spend (total +
   * segment breakdown), PERSIST the leg patch and a durable learned preference,
   * and return `{ patch, ripple:{changed}, learned }`. The persisted preference
   * is what makes the NEXT `get()` lead with a different suggestion.
   */
  correct: protectedProcedure
    .input(
      z.object({
        tripId: z.string().default("north"),
        targetId: z.string(),
        answer: z.string().trim().min(1).max(2_000),
      }),
    )
    .mutation(({ input, ctx }) => {
      const seed = SEEDS[input.tripId];
      const leg = seed?.legs.find((l) => l.id === input.targetId);

      // Scripted reconcile (the seeded wrong leg) — full spend recompute + a real
      // preference update.
      const rule = leg ? ruleFor(input.targetId, input.answer) : null;
      if (seed && leg && rule) {
        const newFare = formatFare(rule.fareRupees);
        const patch: LegPatch = {
          mode: rule.mode,
          fare: newFare,
          fareRupees: rule.fareRupees,
          booked: rule.booked,
          correctedByUser: true,
          segmentDelta: rule.segmentDelta,
        };

        // Persist the overlay patch, then derive the new trip to get the authoritative
        // recomputed spend (deterministic — folds in every applied patch).
        const overlay = writeOverlay(ctx.userId, input.tripId, (o) => ({
          ...o,
          legPatches: { ...o.legPatches, [input.targetId]: patch },
        }));
        const prefs = persistPreference(ctx.userId, input.tripId, rule, input.answer);
        const derived = deriveTrip(seed, overlay, prefs);

        return {
          patch: {
            leg: { id: leg.id, mode: rule.mode, fare: newFare, booked: rule.booked, correctedByUser: true },
            spend: { total: derived.spend.total, segments: derived.spend.segments },
          },
          ripple: { changed: rule.changed(derived.spend.total) },
          learned: rule.learned,
        };
      }

      // Generic fallback — any other past leg/stop still reconciles + teaches, but
      // without a scripted spend shift. We record the user's words as the new note
      // and a soft preference so the correction is durable.
      const learned = `Noted — I'll remember that: ${input.answer}.`;
      const overlay = writeOverlay(ctx.userId, input.tripId, (o) => ({
        ...o,
        legPatches: {
          ...o.legPatches,
          [input.targetId]: {
            mode: input.answer,
            fare: leg?.fare ?? "",
            fareRupees: parseFare(leg?.fare ?? ""),
            booked: leg?.booked ?? true,
            correctedByUser: true,
            segmentDelta: {},
          },
        },
      }));
      void overlay;
      return {
        patch: {
          leg: { id: input.targetId, mode: input.answer, correctedByUser: true },
          spend: null,
        },
        ripple: { changed: "Updated — I've taken that on board." },
        learned,
      };
    }),

  /**
   * Grant a connector (consent for a source).
   *
   * Flips the source available→feeding, rewrites its role + unlock copy to what
   * she can now do, persists the grant, and marks the chapter for re-derivation
   * (so a real build would backfill the granted source and re-derive the affected
   * sections — spend itemisation, live seats, return planning). Idempotent.
   */
  grantConnector: protectedProcedure
    .input(z.object({ tripId: z.string().default("north"), id: z.string() }))
    .mutation(({ input, ctx }) => {
      const seed = SEEDS[input.tripId];
      const connector = seed?.connectors.find((c) => c.id === input.id);
      if (!seed || !connector) {
        return {
          status: "feeding" as const,
          role: "Feeding the chapter now.",
          unlockCopy: "Linked — feeding the chapter now.",
          needsRederive: false,
        };
      }

      const copy = grantCopyFor(connector);
      const grant: ConnectorGrant = {
        status: "feeding",
        role: copy.role,
        unlockCopy: copy.unlockCopy,
        grantedAt: new Date().toISOString(),
      };
      writeOverlay(ctx.userId, input.tripId, (o) => ({
        ...o,
        connectorGrants: { ...o.connectorGrants, [input.id]: grant },
        // A newly-fed source means the chapter should re-derive on the next read.
        needsRederive: true,
      }));

      return {
        status: "feeding" as const,
        role: copy.role,
        unlockCopy: copy.unlockCopy,
        needsRederive: true,
      };
    }),
});

/**
 * Persist (upsert) the preference a correction taught, bumping `weight` on a
 * re-teach. Returns the refreshed learned-prefs summary so the caller can derive
 * the retuned trip in the same request.
 */
function persistPreference(
  userId: string,
  tripId: string,
  rule: CorrectionRule,
  evidence: string,
): LearnedPrefs {
  const now = new Date().toISOString();
  const existing = db
    .select({ id: tripPreferences.id, weight: tripPreferences.weight })
    .from(tripPreferences)
    .where(
      and(
        eq(tripPreferences.userId, userId),
        eq(tripPreferences.tripId, tripId),
        eq(tripPreferences.prefKey, rule.prefKey),
      ),
    )
    .get();
  if (existing) {
    db.update(tripPreferences)
      .set({
        prefValue: rule.prefValue,
        learned: rule.learned,
        evidence,
        weight: existing.weight + 1,
        updatedAt: now,
      })
      .where(eq(tripPreferences.id, existing.id))
      .run();
  } else {
    db.insert(tripPreferences)
      .values({
        id: randomUUID(),
        userId,
        tripId,
        prefKey: rule.prefKey,
        prefValue: rule.prefValue,
        learned: rule.learned,
        evidence,
        updatedAt: now,
      })
      .run();
  }
  return loadPrefs(userId, tripId);
}
