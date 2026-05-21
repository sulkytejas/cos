"use client";
/**
 * Brief detail — renders one brief via BriefRenderer. Sticky action footer
 * at the bottom uses the brief's primary + secondary action strings.
 */
import { useParams, useRouter } from "next/navigation";
import Link from "next/link";
import { trpc } from "@/lib/trpc";
import { BriefRenderer } from "@/components/brief/BriefRenderer";
import { ActionStrip } from "@/components/brief/sections";

export default function BriefDetailPage() {
  const params = useParams<{ id: string }>();
  const router = useRouter();
  const briefQuery = trpc.brief.byId.useQuery(params.id);
  const setStatus = trpc.brief.setStatus.useMutation({
    onSuccess: () => router.push("/"),
  });

  const b = briefQuery.data;
  if (!b) {
    return (
      <div style={{ padding: "60px 0", textAlign: "center" }}>
        <p
          className="serif-i"
          style={{ fontStyle: "italic", color: "var(--color-ink-faint)" }}
        >
          {briefQuery.isLoading ? "Loading the brief…" : "No brief here."}
        </p>
      </div>
    );
  }

  return (
    <div className="pt-4 pb-32">
      <div className="mb-6">
        <Link
          href="/"
          className="font-mono inline-flex items-center gap-1.5"
          style={{
            fontSize: 11.5,
            color: "var(--color-ink-3)",
            letterSpacing: "0.08em",
            textTransform: "uppercase",
          }}
        >
          ← Today
        </Link>
      </div>

      {/* Masthead */}
      <section style={{ padding: "8px 0 22px" }}>
        <div
          className="font-mono"
          style={{
            fontSize: 9.5,
            letterSpacing: "0.22em",
            textTransform: "uppercase",
            color: "var(--color-ink-3)",
            marginBottom: 12,
          }}
        >
          {b.chapterTitle ?? "—"} {b.relevance ? `· ${b.relevance}` : ""}
        </div>
        <h1
          className="serif-i"
          style={{
            margin: 0,
            fontSize: 42,
            lineHeight: 1.05,
            fontStyle: "italic",
            color: "var(--color-ink)",
            letterSpacing: "-0.012em",
            textWrap: "balance",
          }}
        >
          {b.title}
        </h1>
        {b.situationDescription && (
          <p
            style={{
              marginTop: 12,
              fontSize: 15,
              lineHeight: 1.5,
              color: "var(--color-ink-2)",
              maxWidth: 640,
            }}
          >
            {b.situationDescription}
          </p>
        )}
        <div
          style={{
            marginTop: 16,
            display: "flex",
            alignItems: "center",
            gap: 10,
            flexWrap: "wrap",
          }}
        >
          {b.when && (
            <span
              className="font-mono"
              style={{ fontSize: 10, color: "var(--color-teal-deep)", letterSpacing: "0.08em" }}
            >
              {b.when}
            </span>
          )}
          {b.when && b.drafted && (
            <span style={{ width: 1, height: 10, background: "var(--color-hairline)" }} />
          )}
          {b.drafted && (
            <span
              className="font-mono"
              style={{ fontSize: 10, color: "var(--color-ink-4)", letterSpacing: "0.08em" }}
            >
              {b.drafted}
            </span>
          )}
        </div>
      </section>

      <div className="hairline" style={{ borderBottom: "1px solid var(--color-hairline)", margin: "0 0 0 0" }} />

      {/* Sections */}
      <div style={{ paddingBottom: 24 }}>
        <BriefRenderer briefId={b.id} structure={b.structure} />
      </div>

      {/* Sticky action strip */}
      <div
        style={{
          position: "sticky",
          bottom: 0,
          padding: "14px 0",
          borderTop: "1px solid var(--color-hairline)",
          background: "var(--color-paper)",
        }}
      >
        <ActionStrip
          data={{
            primary: b.primaryAction ?? "Open",
            secondary: b.secondaryActions ?? ["Snooze", "Dismiss"],
          }}
        />
        <div style={{ display: "flex", gap: 12, marginTop: 8 }}>
          <button
            className="font-mono"
            style={{
              fontSize: 10.5,
              letterSpacing: "0.16em",
              textTransform: "uppercase",
              color: "var(--color-ink-3)",
            }}
            onClick={() => setStatus.mutate({ id: b.id, status: "dismissed" })}
          >
            Dismiss
          </button>
          <button
            className="font-mono"
            style={{
              fontSize: 10.5,
              letterSpacing: "0.16em",
              textTransform: "uppercase",
              color: "var(--color-ink-3)",
            }}
            onClick={() => setStatus.mutate({ id: b.id, status: "acted_on" })}
          >
            Mark acted on
          </button>
        </div>
      </div>
    </div>
  );
}
