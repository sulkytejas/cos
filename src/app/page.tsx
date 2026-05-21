"use client";
/**
 * Today — v0.2 layout. Five blocks, in order:
 *   • Date headline + next milestone strip
 *   • "Handled while you slept" line (counts from signals + filed proposals)
 *   • "Briefs for today" (from briefs.forToday)
 *   • "Atlas is watching" (from watchers.active)
 *   • "Up next" todos (carried over from v0.1, kept slim)
 */
import Link from "next/link";
import { trpc } from "@/lib/trpc";
import { format } from "date-fns";
import { BriefTeaserCard, WatcherLine } from "@/components/brief/teasers";
import { dueClass, fmtDate } from "@/lib/utils";
import { TypeIcon } from "@/components/TypeIcon";

export default function TodayPage() {
  const today = new Date();

  const briefsQuery = trpc.brief.forToday.useQuery();
  const watchersQuery = trpc.watcher.active.useQuery();
  const overnightQuery = trpc.signal.overnight.useQuery();
  const proposalCountsQuery = trpc.proposal.countsForToday.useQuery();
  const todosQuery = trpc.todo.topAcrossActive.useQuery({ limit: 5 });

  const briefs = briefsQuery.data ?? [];
  const watchers = watchersQuery.data ?? [];

  return (
    <div className="space-y-10 pt-6 pb-20">
      {/* Date headline + "next" strip */}
      <section>
        <p
          className="font-mono"
          style={{
            fontSize: 10,
            letterSpacing: "0.18em",
            textTransform: "uppercase",
            color: "var(--color-ink-3)",
            marginBottom: 6,
          }}
        >
          {format(today, "EEEE")}
        </p>
        <h1
          className="serif-i"
          style={{
            margin: 0,
            fontSize: 72,
            lineHeight: 0.92,
            fontStyle: "italic",
            color: "var(--color-ink)",
            letterSpacing: "-0.018em",
          }}
        >
          {format(today, "MMMM d")}
        </h1>
        {briefs[0] && (
          <div style={{ marginTop: 12, display: "flex", alignItems: "center", gap: 8 }}>
            <span className="pulse-dot" />
            <span className="micro">Next</span>
            {briefs[0].when && (
              <span
                className="font-mono"
                style={{ fontSize: 11, color: "var(--color-teal-deep)", letterSpacing: "0.04em" }}
              >
                {briefs[0].when}
              </span>
            )}
            <span
              className="serif-i"
              style={{ fontStyle: "italic", fontSize: 14, color: "var(--color-ink-2)" }}
            >
              {briefs[0].title}
            </span>
            <span style={{ flex: 1, height: 1, background: "var(--color-hairline-soft)", marginLeft: 4 }} />
          </div>
        )}
      </section>

      <HandledWhileYouSlept
        signalBuckets={overnightQuery.data?.buckets ?? {}}
        totalSignals={overnightQuery.data?.total ?? 0}
        filedByType={proposalCountsQuery.data?.filedByType ?? {}}
      />

      {/* Briefs for today */}
      <section>
        <div className="flex items-baseline justify-between" style={{ marginBottom: 12 }}>
          <h2 className="font-serif" style={{ fontSize: 22, color: "var(--color-ink)" }}>
            Briefs for today
          </h2>
          <span
            className="font-mono"
            style={{
              fontSize: 9.5,
              color: "var(--color-ink-3)",
              letterSpacing: "0.16em",
              textTransform: "uppercase",
            }}
          >
            {briefs.length} {briefs.length === 1 ? "ready" : "ready"}
          </span>
        </div>
        {briefs.length === 0 ? (
          <p
            className="serif-i"
            style={{
              fontStyle: "italic",
              color: "var(--color-ink-faint)",
              fontSize: 15,
              padding: "20px 0",
            }}
          >
            Nothing surfaced yet. Atlas will draft briefs as situations form.
          </p>
        ) : (
          <div className="flex flex-col gap-3">
            {briefs.map((b, i) => (
              <BriefTeaserCard
                key={b.id}
                brief={{
                  id: b.id,
                  title: b.title,
                  preview: b.preview,
                  chapterTitle: b.chapterTitle,
                  when: b.when,
                  urgent: i === 0,
                }}
              />
            ))}
          </div>
        )}
      </section>

      {/* Atlas is watching */}
      <section>
        <div className="flex items-baseline justify-between" style={{ marginBottom: 6 }}>
          <h2 className="font-serif" style={{ fontSize: 22, color: "var(--color-ink)" }}>
            Atlas is watching
          </h2>
          <span
            className="font-mono"
            style={{
              fontSize: 9.5,
              color: "var(--color-ink-3)",
              letterSpacing: "0.16em",
              textTransform: "uppercase",
            }}
          >
            {watchers.length} active
          </span>
        </div>
        {watchers.length === 0 ? (
          <p
            className="serif-i"
            style={{ fontStyle: "italic", color: "var(--color-ink-faint)", fontSize: 14, padding: "10px 0" }}
          >
            Nothing on watch. Atlas adds watchers when it spots something worth checking back on.
          </p>
        ) : (
          <div>
            {watchers.slice(0, 5).map((w) => (
              <WatcherLine
                key={w.id}
                w={{ id: w.id, description: w.description, cadenceLabel: w.cadenceLabel }}
              />
            ))}
          </div>
        )}
      </section>

      {/* Up next — todos kept slim */}
      <section>
        <div className="flex items-baseline justify-between" style={{ marginBottom: 12 }}>
          <h2 className="font-serif" style={{ fontSize: 22, color: "var(--color-ink)" }}>
            Up next
          </h2>
          <Link
            href="/chapters"
            className="font-mono"
            style={{
              fontSize: 10,
              color: "var(--color-ink-3)",
              letterSpacing: "0.16em",
              textTransform: "uppercase",
            }}
          >
            All chapters →
          </Link>
        </div>
        <ul className="card divide-y divide-[color:var(--color-border-warm)]">
          {(todosQuery.data ?? []).length === 0 ? (
            <li className="px-5 py-6 text-sm" style={{ color: "var(--color-ink-secondary)" }}>
              No active todos. Capture something with <span className="kbd">⌘K</span>.
            </li>
          ) : (
            (todosQuery.data ?? []).map((t) => (
              <li key={t.id} className="flex items-start gap-4 px-5 py-4">
                <div
                  className="mt-1 h-3.5 w-3.5 shrink-0 rounded-sm"
                  style={{
                    border:
                      t.source === "manual"
                        ? "1px solid var(--color-border-warm-strong)"
                        : "1px solid var(--color-forest)",
                    background:
                      t.source === "manual" ? "transparent" : "transparent",
                  }}
                  aria-label={`source ${t.source}`}
                />
                <div className="flex-1 min-w-0">
                  <p style={{ fontSize: 14, color: "var(--color-ink)", lineHeight: 1.4 }}>{t.text}</p>
                  <div
                    className="flex items-center gap-3 mt-1"
                    style={{ fontSize: 11, color: "var(--color-ink-faint)" }}
                  >
                    <Link
                      href={`/chapter/${t.chapterId}`}
                      className="flex items-center gap-1.5 hover:text-ink"
                    >
                      <TypeIcon type={t.chapterType} className="h-3 w-3" />
                      <span>{t.chapterTitle}</span>
                    </Link>
                    {t.dueDate && (
                      <span className={`font-mono ${dueClass(t.dueDate)}`}>{fmtDate(t.dueDate)}</span>
                    )}
                  </div>
                </div>
              </li>
            ))
          )}
        </ul>
      </section>
    </div>
  );
}

function HandledWhileYouSlept({
  signalBuckets,
  totalSignals,
  filedByType,
}: {
  signalBuckets: Record<string, number>;
  totalSignals: number;
  filedByType: Record<string, number>;
}) {
  // Compose a one-line summary sentence in Atlas's voice.
  const parts: string[] = [];
  if (signalBuckets.gmail > 5) parts.push(`Filed ${signalBuckets.gmail} newsletters`);
  if (filedByType.todo) parts.push(`drafted ${filedByType.todo} todos`);
  if (filedByType.decision) parts.push(`noted ${filedByType.decision} decision`);
  if (filedByType.journal_entry || filedByType.journal) {
    const n = (filedByType.journal_entry ?? 0) + (filedByType.journal ?? 0);
    parts.push(`saved ${n} journal entr${n === 1 ? "y" : "ies"}`);
  }
  const sentence =
    parts.length === 0
      ? totalSignals > 0
        ? `Handled ${totalSignals} small signals overnight; nothing flagged for review.`
        : "Nothing came in overnight."
      : parts.join(" · ");

  return (
    <section
      style={{
        padding: "12px 0 14px",
        borderTop: "1px solid var(--color-hairline)",
        borderBottom: "1px solid var(--color-hairline)",
      }}
    >
      <div style={{ display: "flex", alignItems: "baseline", gap: 8, marginBottom: 6 }}>
        <span
          className="font-mono"
          style={{
            fontSize: 9,
            letterSpacing: "0.2em",
            textTransform: "uppercase",
            color: "var(--color-ink-3)",
          }}
        >
          Handled while you slept
        </span>
        <span
          className="font-mono"
          style={{ fontSize: 9, color: "var(--color-ink-4)", letterSpacing: "0.06em" }}
        >
          · overnight
        </span>
      </div>
      <div
        className="font-mono"
        style={{
          fontSize: 11.5,
          lineHeight: 1.55,
          color: "var(--color-ink-2)",
          letterSpacing: "0.01em",
        }}
      >
        {sentence}.{" "}
        <Link href="/review" style={{ color: "var(--color-teal-deep)" }}>
          Review them →
        </Link>
      </div>
    </section>
  );
}
