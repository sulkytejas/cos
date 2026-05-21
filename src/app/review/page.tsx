"use client";
/**
 * /review — the Morning Page. In v0.2 the prototype's ReviewQueueScreenLive
 * was literally `return <MorningPageScreen page={...} />` — the Morning Page
 * IS the review experience. Power-user proposal queue moves to /review/queue.
 */
import Link from "next/link";
import { trpc } from "@/lib/trpc";
import { MorningPage } from "@/components/morning/MorningPage";

export default function ReviewPage() {
  const morningQuery = trpc.morning.latest.useQuery();
  const page = morningQuery.data;

  return (
    <div className="max-w-2xl mx-auto">
      {page ? (
        <MorningPage page={page} />
      ) : (
        <div className="py-20 text-center">
          <p
            className="serif-i"
            style={{
              fontStyle: "italic",
              color: "var(--color-ink-faint)",
              fontSize: 15,
            }}
          >
            {morningQuery.isLoading
              ? "Atlas is reading the overnight signals…"
              : "No morning page yet."}
          </p>
        </div>
      )}

      <div
        style={{
          marginTop: 32,
          paddingTop: 16,
          borderTop: "1px solid var(--color-hairline-soft)",
          fontFamily: "var(--font-mono)",
          fontSize: 10,
          letterSpacing: "0.16em",
          textTransform: "uppercase",
          color: "var(--color-ink-3)",
        }}
      >
        <Link href="/review/queue" style={{ color: "inherit" }}>
          See all proposals →
        </Link>
      </div>
    </div>
  );
}
