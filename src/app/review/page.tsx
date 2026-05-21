"use client";
/**
 * Review Queue — `pending` proposals at the top (Atlas's small unsure
 * questions), and a quieter "Atlas filed:" list below for high-confidence
 * items the user can scan and ignore.
 */
import { useState } from "react";
import { trpc } from "@/lib/trpc";
import { SourcePill } from "@/components/brief/primitives";

type FilterType = "all" | "todo" | "decision" | "journal_entry" | "chapter_link";

export default function ReviewPage() {
  const [filter, setFilter] = useState<FilterType>("all");
  const queueQuery = trpc.proposal.forReview.useQuery({
    type: filter === "all" ? undefined : (filter as never),
  });
  const utils = trpc.useUtils();
  const approve = trpc.proposal.approve.useMutation({
    onSuccess: () => utils.proposal.forReview.invalidate(),
  });
  const dismiss = trpc.proposal.dismiss.useMutation({
    onSuccess: () => utils.proposal.forReview.invalidate(),
  });

  const pending = queueQuery.data?.pending ?? [];
  const filedToday = queueQuery.data?.filedToday ?? [];

  return (
    <div className="pt-6 pb-20 space-y-10">
      <header>
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
          Review
        </p>
        <h1
          className="serif-i"
          style={{
            margin: 0,
            fontSize: 56,
            lineHeight: 0.92,
            fontStyle: "italic",
            color: "var(--color-ink)",
            letterSpacing: "-0.015em",
          }}
        >
          What I'm unsure about
        </h1>
        <p
          style={{
            marginTop: 14,
            fontSize: 14,
            color: "var(--color-ink-2)",
            maxWidth: 560,
            lineHeight: 1.55,
          }}
        >
          A few small things from overnight. Anything I was confident about is filed already and shown below for the record.
        </p>
      </header>

      <FilterChips current={filter} onChange={setFilter} />

      {/* Pending — asks */}
      <section>
        <SectionHeading
          label="Asked"
          meta={`${pending.length} ${pending.length === 1 ? "question" : "questions"}`}
        />
        {pending.length === 0 ? (
          <p
            className="serif-i"
            style={{
              fontStyle: "italic",
              color: "var(--color-ink-faint)",
              fontSize: 15,
              padding: "20px 0",
            }}
          >
            Nothing to weigh in on right now.
          </p>
        ) : (
          <div className="flex flex-col gap-5">
            {pending.map((p) => (
              <AskCard
                key={p.id}
                proposal={p}
                onChoose={(chosenValue) =>
                  approve.mutate({ id: p.id, chosenValue })
                }
                onDismiss={() => dismiss.mutate(p.id)}
              />
            ))}
          </div>
        )}
      </section>

      {/* Filed — quiet log of what Atlas filed without bothering you */}
      <section>
        <SectionHeading
          label="Atlas filed"
          meta={`${filedToday.length} today`}
        />
        {filedToday.length === 0 ? (
          <p
            className="serif-i"
            style={{
              fontStyle: "italic",
              color: "var(--color-ink-faint)",
              fontSize: 14,
              padding: "10px 0",
            }}
          >
            Nothing filed yet today.
          </p>
        ) : (
          <ul style={{ borderTop: "1px solid var(--color-hairline-soft)" }}>
            {filedToday.map((p) => (
              <li
                key={p.id}
                style={{
                  display: "flex",
                  alignItems: "baseline",
                  gap: 12,
                  padding: "12px 0",
                  borderBottom: "1px solid var(--color-hairline-soft)",
                }}
              >
                <span
                  aria-label="filed"
                  style={{
                    width: 7,
                    height: 7,
                    borderRadius: "50%",
                    border: "1px solid var(--color-forest)",
                    flexShrink: 0,
                  }}
                />
                <span style={{ flex: 1, fontSize: 13.5, color: "var(--color-ink)", lineHeight: 1.4 }}>
                  {p.summary ?? "(no summary)"}
                </span>
                <SourcePill source={p.sourceLabel ?? "Inferred"} sub={p.sourceMeta} />
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}

function SectionHeading({ label, meta }: { label: string; meta: string }) {
  return (
    <div
      className="flex items-baseline justify-between"
      style={{ marginBottom: 12 }}
    >
      <h2 className="font-serif" style={{ fontSize: 22, color: "var(--color-ink)" }}>
        {label}
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
        {meta}
      </span>
    </div>
  );
}

function FilterChips({
  current,
  onChange,
}: {
  current: FilterType;
  onChange: (f: FilterType) => void;
}) {
  const options: { id: FilterType; label: string }[] = [
    { id: "all", label: "All" },
    { id: "todo", label: "Todos" },
    { id: "decision", label: "Decisions" },
    { id: "journal_entry", label: "Journal" },
    { id: "chapter_link", label: "Links" },
  ];
  return (
    <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
      {options.map((o) => {
        const active = current === o.id;
        return (
          <button
            key={o.id}
            onClick={() => onChange(o.id)}
            style={{
              padding: "5px 11px",
              border: "1px solid",
              borderColor: active ? "var(--color-ink)" : "var(--color-hairline)",
              background: active ? "var(--color-ink)" : "transparent",
              color: active ? "#fff" : "var(--color-ink-2)",
              borderRadius: 4,
              fontFamily: "var(--font-mono)",
              fontSize: 10.5,
              letterSpacing: "0.12em",
              textTransform: "uppercase",
              cursor: "pointer",
            }}
          >
            {o.label}
          </button>
        );
      })}
    </div>
  );
}

interface ProposalShape {
  id: string;
  type: string;
  summary: string | null;
  sourceLabel: string | null;
  sourceMeta: string | null;
  setup: string | null;
  question: string | null;
  options: unknown;
  reasoning: string | null;
}

function AskCard({
  proposal,
  onChoose,
  onDismiss,
}: {
  proposal: ProposalShape;
  onChoose: (chosenValue: string) => void;
  onDismiss: () => void;
}) {
  const opts =
    (proposal.options as Array<{ label: string; value: string; result?: string }> | null) ?? [];
  return (
    <div
      style={{
        padding: "16px 18px",
        border: "1px solid var(--color-hairline)",
        borderRadius: 6,
        background: "var(--color-bg-elev)",
      }}
    >
      <div style={{ marginBottom: 10 }}>
        <SourcePill source={proposal.sourceLabel ?? "Inferred"} sub={proposal.sourceMeta} />
      </div>
      {proposal.setup && (
        <p
          className="serif-i"
          style={{
            fontStyle: "italic",
            fontSize: 17,
            lineHeight: 1.5,
            color: "var(--color-ink)",
            marginBottom: 14,
            textWrap: "balance",
          }}
        >
          {proposal.setup}
        </p>
      )}
      {proposal.question && (
        <p style={{ fontSize: 14, color: "var(--color-ink-2)", marginBottom: 10 }}>
          {proposal.question}
        </p>
      )}
      <div style={{ display: "flex", gap: 10, flexWrap: "wrap" }}>
        {opts.map((o) => (
          <button
            key={o.value}
            onClick={() => onChoose(o.value)}
            className="pressable serif-i"
            style={{
              fontStyle: "italic",
              fontSize: 15,
              padding: "8px 14px",
              borderRadius: 4,
              border: "1px solid var(--color-ink)",
              background: "transparent",
              color: "var(--color-ink)",
              cursor: "pointer",
            }}
            title={o.result}
          >
            {o.label}
          </button>
        ))}
        <button
          onClick={onDismiss}
          style={{
            padding: "8px 12px",
            borderRadius: 4,
            border: "1px solid var(--color-hairline)",
            background: "transparent",
            color: "var(--color-ink-3)",
            cursor: "pointer",
            fontFamily: "var(--font-sans)",
            fontSize: 13,
          }}
        >
          Not now
        </button>
      </div>
      {opts[0]?.result && (
        <p
          style={{
            marginTop: 10,
            fontSize: 12,
            color: "var(--color-ink-faint)",
            fontStyle: "italic",
          }}
        >
          {opts[0].result}
        </p>
      )}
    </div>
  );
}
