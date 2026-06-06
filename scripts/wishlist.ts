/**
 * Dev wishlist — the modules Atlas wished existed (Today agentic flow v1).
 *
 * The worker logs its deliberate wishes into `dev_unknown_components`: chapter
 * `missing_modules` (named modules it wanted but we hadn't built, source:'palette')
 * and morning-turn connector suggestions naming an unsupported source (whatsapp, a
 * bank — source:'connector', never a user CTA, only a builder signal). This script
 * reads that ledger, groups by component name, and prints — sorted by how many
 * times each was wanted — the count, the one-line spec, the chapter that wanted it
 * (when any), and when it was last logged. It's a standing TODO list authored by
 * the agent.
 *
 *   pnpm wishlist
 */
import { db } from "../src/db/client";
import { devUnknownComponents } from "../src/db/schema";

type RawProps = {
  spec?: string;
  chapterId?: string;
  source?: string;
} | null;

function main() {
  const all = db.select().from(devUnknownComponents).all();

  // Several writers share this table with different rawProps shapes. The
  // deliberate AGENT WISHES carry an explicit `source` tag and belong in the
  // wishlist proper:
  //   - `source: 'palette'`   — chapter `missing_modules`, a named module the
  //     agent wished the library had (counted once per run).
  //   - `source: 'connector'` — a morning-turn connector suggestion naming an
  //     UNSUPPORTED source (whatsapp, a bank): not a user CTA, but a real
  //     observed gap the builders should weigh (componentName 'connector:<src>').
  // By contrast the BriefRenderer logs `rawProps: structure` on EVERY render of a
  // brief with an unknown kind (no `source`, and a count inflated by view
  // repeats). Mixing those in would conflate "wished N times" with "viewed N
  // times", so the renderer strays stay excluded and are summarized separately
  // below as a one-line footer.
  const WISH_SOURCES = ["palette", "connector"];
  const rows = all.filter((r) => WISH_SOURCES.includes((r.rawProps as RawProps)?.source ?? ""));
  const renderStrays = all.length - rows.length;

  if (rows.length === 0) {
    console.log("[atlas wishlist] nothing wished yet — no palette/connector wishes logged.");
    if (renderStrays > 0) {
      console.log(
        `[atlas wishlist] (${renderStrays} renderer log(s) of unknown kinds exist — inspect dev_unknown_components directly.)`
      );
    }
    return;
  }

  // Group by component name: count, the most recent spec/chapter, last loggedAt.
  const grouped = new Map<
    string,
    { count: number; spec: string; chapterId: string; lastLoggedAt: string }
  >();

  for (const r of rows) {
    const props = (r.rawProps as RawProps) ?? null;
    const existing = grouped.get(r.componentName);
    const loggedAt = r.loggedAt;
    if (existing) {
      existing.count += 1;
      // Keep the most-recent non-empty spec/chapter for the row.
      if (loggedAt >= existing.lastLoggedAt) {
        existing.lastLoggedAt = loggedAt;
        if (props?.spec) existing.spec = props.spec;
        if (props?.chapterId) existing.chapterId = props.chapterId;
      } else {
        if (!existing.spec && props?.spec) existing.spec = props.spec;
        if (!existing.chapterId && props?.chapterId) existing.chapterId = props.chapterId;
      }
    } else {
      grouped.set(r.componentName, {
        count: 1,
        spec: props?.spec ?? "",
        chapterId: props?.chapterId ?? "",
        lastLoggedAt: loggedAt,
      });
    }
  }

  // Sorted by count desc — the most-wanted modules float to the top.
  const sorted = [...grouped.entries()].sort((a, b) => b[1].count - a[1].count);

  console.log(`\n[atlas wishlist] ${rows.length} wish(es) across ${sorted.length} module(s)\n`);
  console.table(
    sorted.map(([name, v]) => ({
      module: name,
      count: v.count,
      spec: v.spec || "—",
      chapterId: v.chapterId || "—",
      lastLoggedAt: v.lastLoggedAt,
    }))
  );
  if (renderStrays > 0) {
    console.log(`(+ ${renderStrays} renderer log(s) of unknown kinds, excluded from the wish counts.)`);
  }
}

main();
