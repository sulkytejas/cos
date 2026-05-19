"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useCapture } from "./CaptureProvider";
import { trpc } from "@/lib/trpc";
import { X, CheckSquare, Lightbulb, BookOpen, Loader2 } from "lucide-react";
import { cn } from "@/lib/utils";

type Kind = "todo" | "decision" | "entry";

export function CaptureModal() {
  const { close, preselectedChapterId } = useCapture();
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const [text, setText] = useState("");
  const [chapterId, setChapterId] = useState<string | null>(null);

  const utils = trpc.useUtils();
  const chaptersQuery = trpc.chapter.recentlyActive.useQuery();
  const todoCreate = trpc.todo.create.useMutation();
  const decisionCreate = trpc.decision.create.useMutation();
  const entryCreate = trpc.entry.create.useMutation();

  const pending =
    todoCreate.isPending || decisionCreate.isPending || entryCreate.isPending;

  useEffect(() => {
    textareaRef.current?.focus();
  }, []);

  useEffect(() => {
    if (preselectedChapterId) {
      setChapterId(preselectedChapterId);
      return;
    }
    if (chaptersQuery.data && !chapterId) {
      const active = chaptersQuery.data.find((c) => c.status === "active");
      setChapterId((active ?? chaptersQuery.data[0])?.id ?? null);
    }
  }, [chaptersQuery.data, chapterId, preselectedChapterId]);

  const submit = useMemo(
    () => async (kind: Kind) => {
      if (!chapterId || !text.trim()) return;

      if (kind === "todo") {
        await todoCreate.mutateAsync({ chapterId, text: text.trim() });
      } else if (kind === "decision") {
        await decisionCreate.mutateAsync({
          chapterId,
          title: text.trim().split("\n")[0]!.slice(0, 120),
          rationale: text.trim(),
        });
      } else {
        await entryCreate.mutateAsync({ chapterId, content: text.trim() });
      }

      await Promise.all([
        utils.chapter.list.invalidate(),
        utils.chapter.get.invalidate(),
        utils.todo.topAcrossActive.invalidate(),
      ]);

      setText("");
      close();
    },
    [chapterId, text, todoCreate, decisionCreate, entryCreate, utils, close]
  );

  return (
    <div
      className="fixed inset-0 z-40 flex items-start justify-center bg-[rgba(26,24,20,0.35)] px-4 pt-[10vh] sm:pt-[15vh]"
      onClick={close}
    >
      <div
        className="card fade-in w-full max-w-xl overflow-hidden"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="hairline-b flex items-center justify-between px-5 py-3">
          <span className="font-mono text-xs uppercase tracking-widest text-ink-faint">
            Capture
          </span>
          <button onClick={close} className="text-ink-faint hover:text-ink">
            <X className="h-4 w-4" />
          </button>
        </div>

        <div className="p-5">
          <textarea
            ref={textareaRef}
            value={text}
            onChange={(e) => setText(e.target.value)}
            placeholder="What just happened? What needs to happen?"
            rows={5}
            className="input-bare resize-none text-base leading-relaxed placeholder:text-ink-faint"
          />
        </div>

        <div className="hairline-t flex flex-col gap-3 px-5 py-4 sm:flex-row sm:items-center sm:justify-between">
          <label className="flex items-center gap-2 text-xs text-ink-secondary">
            <span className="font-mono uppercase tracking-widest text-[10px] text-ink-faint">
              chapter
            </span>
            <select
              value={chapterId ?? ""}
              onChange={(e) => setChapterId(e.target.value || null)}
              className="field py-1.5 text-sm"
            >
              {chaptersQuery.data?.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.title}
                </option>
              ))}
            </select>
          </label>

          <div className="flex flex-wrap items-center gap-2">
            <ActionButton
              icon={<CheckSquare className="h-4 w-4" />}
              label="Todo"
              onClick={() => submit("todo")}
              disabled={pending || !text.trim() || !chapterId}
              loading={todoCreate.isPending}
            />
            <ActionButton
              icon={<Lightbulb className="h-4 w-4" />}
              label="Decision"
              onClick={() => submit("decision")}
              disabled={pending || !text.trim() || !chapterId}
              loading={decisionCreate.isPending}
            />
            <ActionButton
              icon={<BookOpen className="h-4 w-4" />}
              label="Journal"
              onClick={() => submit("entry")}
              disabled={pending || !text.trim() || !chapterId}
              loading={entryCreate.isPending}
              primary
            />
          </div>
        </div>
      </div>
    </div>
  );
}

function ActionButton({
  icon,
  label,
  onClick,
  disabled,
  loading,
  primary,
}: {
  icon: React.ReactNode;
  label: string;
  onClick: () => void;
  disabled?: boolean;
  loading?: boolean;
  primary?: boolean;
}) {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      className={cn(
        primary ? "btn-primary" : "btn-ghost",
        "disabled:opacity-40 disabled:pointer-events-none"
      )}
    >
      {loading ? <Loader2 className="h-4 w-4 animate-spin" /> : icon}
      <span>{label}</span>
    </button>
  );
}
