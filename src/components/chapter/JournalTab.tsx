"use client";

import { useState } from "react";
import { trpc } from "@/lib/trpc";
import { fmtDate, fmtRelative, cn } from "@/lib/utils";
import { Plus, Loader2, Trash2 } from "lucide-react";
import type { EntrySource } from "@/db/schema";

type Entry = {
  id: string;
  content: string;
  date: string;
  source: EntrySource;
};

type ChapterShape = {
  id: string;
  entries: Entry[];
};

export function JournalTab({ chapter }: { chapter: ChapterShape }) {
  const [text, setText] = useState("");
  const utils = trpc.useUtils();
  const invalidate = () => utils.chapter.get.invalidate(chapter.id);

  const create = trpc.entry.create.useMutation({ onSuccess: invalidate });
  const remove = trpc.entry.delete.useMutation({ onSuccess: invalidate });

  async function add() {
    if (!text.trim()) return;
    await create.mutateAsync({
      chapterId: chapter.id,
      content: text.trim(),
    });
    setText("");
  }

  return (
    <div className="space-y-6">
      <div className="card p-4">
        <textarea
          value={text}
          onChange={(e) => setText(e.target.value)}
          rows={3}
          placeholder="Note something. A thought, a meeting, a turn."
          className="input-bare resize-none"
        />
        <div className="hairline-t mt-3 pt-3 flex items-center justify-end">
          <button
            onClick={add}
            disabled={!text.trim() || create.isPending}
            className="btn-primary disabled:opacity-40"
          >
            {create.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Plus className="h-4 w-4" />}
            Add entry
          </button>
        </div>
      </div>

      {chapter.entries.length === 0 ? (
        <p className="text-sm text-ink-faint text-center py-8">
          Nothing logged yet.
        </p>
      ) : (
        <ol className="space-y-5">
          {chapter.entries.map((e) => {
            const passive = e.source !== "manual";
            return (
            <li
              key={e.id}
              className="group flex gap-5"
              style={{ opacity: passive ? 0.78 : 1 }}
            >
              <div className="w-24 shrink-0 pt-1 text-right">
                <p className="font-mono text-[10px] uppercase tracking-widest text-ink-faint">
                  {fmtDate(e.date, "MMM d")}
                </p>
                <p className="font-mono text-[9px] text-ink-faint">
                  {fmtRelative(e.date)}
                </p>
              </div>
              <div className="flex-1 hairline-b pb-5 last:border-0">
                <p
                  className="leading-relaxed whitespace-pre-wrap"
                  style={{
                    fontSize: 15,
                    color: passive ? "var(--color-ink-secondary)" : "var(--color-ink)",
                    fontWeight: passive ? 400 : 500,
                  }}
                >
                  {e.content}
                </p>
                <div className="mt-2 flex items-center justify-between">
                  <span className={cn("chip", sourceClass(e.source))}>
                    {e.source}
                  </span>
                  <button
                    onClick={() => remove.mutate(e.id)}
                    className="opacity-0 group-hover:opacity-100 transition-opacity text-ink-faint hover:text-ember"
                    aria-label="Delete entry"
                  >
                    <Trash2 className="h-3.5 w-3.5" />
                  </button>
                </div>
              </div>
            </li>
          );
          })}
        </ol>
      )}
    </div>
  );
}

function sourceClass(source: EntrySource) {
  if (source === "manual") return "";
  if (source === "email") return "chip-moss";
  if (source === "calendar") return "chip-moss";
  return "chip-moss";
}
