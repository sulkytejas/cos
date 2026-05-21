"use client";
/**
 * Capture — full-page, agentic. User types or paste; on submit we emit a
 * 'capture_received' event and poll its status. The worker turns the text
 * into proposals which the user then reviews at /review.
 */
import { useEffect, useRef, useState } from "react";
import { trpc } from "@/lib/trpc";
import { useRouter } from "next/navigation";

export default function CapturePage() {
  const router = useRouter();
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const [text, setText] = useState("");
  const [chapterId, setChapterId] = useState<string | null>(null);
  const [eventId, setEventId] = useState<string | null>(null);

  const chaptersQuery = trpc.chapter.recentlyActive.useQuery();
  const emitEvent = trpc.event.emit.useMutation({
    onSuccess: ({ id }) => setEventId(id),
  });
  const eventStatus = trpc.event.status.useQuery(eventId ?? "", {
    enabled: !!eventId,
    refetchInterval: (q) => {
      const s = q.state.data?.status;
      return s === "pending" || s === "processing" ? 2000 : false;
    },
  });

  useEffect(() => textareaRef.current?.focus(), []);
  useEffect(() => {
    if (eventStatus.data?.status === "done") {
      router.push("/review");
    }
  }, [eventStatus.data, router]);

  const submit = () => {
    if (!text.trim()) return;
    emitEvent.mutate({
      type: "capture_received",
      payload: { text: text.trim(), chapterId },
    });
  };

  const thinking = eventId && eventStatus.data && eventStatus.data.status !== "done";

  return (
    <div className="pt-12 pb-20 max-w-2xl mx-auto">
      <header style={{ marginBottom: 18 }}>
        <p
          className="font-mono"
          style={{
            fontSize: 9,
            letterSpacing: "0.22em",
            textTransform: "uppercase",
            color: "var(--color-ink-3)",
            marginBottom: 8,
          }}
        >
          Capture
        </p>
        <h1
          className="serif-i"
          style={{
            margin: 0,
            fontSize: 44,
            lineHeight: 1.0,
            fontStyle: "italic",
            color: "var(--color-ink)",
            letterSpacing: "-0.012em",
          }}
        >
          What is it?
        </h1>
      </header>

      <div
        style={{
          border: "1px solid var(--color-hairline)",
          borderRadius: 6,
          background: "var(--color-card)",
          padding: "16px 18px",
        }}
      >
        <textarea
          ref={textareaRef}
          value={text}
          onChange={(e) => setText(e.target.value)}
          placeholder="Type or paste anything. Atlas will figure out what kind of thing it is."
          rows={6}
          className="input-bare resize-none"
          style={{
            width: "100%",
            fontFamily: "var(--font-serif)",
            fontSize: 19,
            lineHeight: 1.5,
            color: "var(--color-ink)",
            background: "transparent",
            border: 0,
            outline: 0,
          }}
        />
        <div
          className="font-mono"
          style={{ textAlign: "right", fontSize: 9.5, color: "var(--color-ink-4)", letterSpacing: "0.08em" }}
        >
          {text.length ? `${text.length} char` : "—"}
        </div>
      </div>

      <div style={{ marginTop: 18, display: "flex", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
        <label style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <span
            className="font-mono"
            style={{
              fontSize: 9,
              letterSpacing: "0.2em",
              textTransform: "uppercase",
              color: "var(--color-ink-3)",
            }}
          >
            Chapter
          </span>
          <select
            value={chapterId ?? ""}
            onChange={(e) => setChapterId(e.target.value || null)}
            className="field"
            style={{ fontSize: 14 }}
          >
            <option value="">unspecified</option>
            {chaptersQuery.data?.map((c) => (
              <option key={c.id} value={c.id}>
                {c.title}
              </option>
            ))}
          </select>
        </label>
        <span style={{ flex: 1 }} />
        <button
          onClick={submit}
          disabled={!text.trim() || !!thinking}
          className="btn-primary"
          style={{ opacity: !text.trim() || thinking ? 0.45 : 1 }}
        >
          {thinking ? "Atlas is thinking…" : "Hand to Atlas"}
        </button>
      </div>

      {thinking && (
        <p
          className="serif-i"
          style={{
            marginTop: 14,
            fontStyle: "italic",
            fontSize: 14,
            color: "var(--color-ink-faint)",
          }}
        >
          Atlas will route this into the Review Queue. You'll see proposals to approve, edit, or dismiss in a moment.
        </p>
      )}
    </div>
  );
}
