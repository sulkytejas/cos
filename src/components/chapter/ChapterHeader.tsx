"use client";

import { useState } from "react";
import { trpc } from "@/lib/trpc";
import { Check, Pencil } from "lucide-react";

type ChapterShape = {
  id: string;
  title: string;
  purpose: string | null;
};

export function ChapterHeader({ chapter }: { chapter: ChapterShape }) {
  const utils = trpc.useUtils();
  const update = trpc.chapter.update.useMutation({
    onSuccess: () => {
      utils.chapter.get.invalidate(chapter.id);
      utils.chapter.list.invalidate();
    },
  });

  const [editingTitle, setEditingTitle] = useState(false);
  const [title, setTitle] = useState(chapter.title);
  const [editingPurpose, setEditingPurpose] = useState(false);
  const [purpose, setPurpose] = useState(chapter.purpose ?? "");

  async function saveTitle() {
    if (title.trim() && title.trim() !== chapter.title) {
      await update.mutateAsync({ id: chapter.id, title: title.trim() });
    } else {
      setTitle(chapter.title);
    }
    setEditingTitle(false);
  }

  async function savePurpose() {
    if (purpose.trim() !== (chapter.purpose ?? "")) {
      await update.mutateAsync({
        id: chapter.id,
        purpose: purpose.trim() || null,
      });
    }
    setEditingPurpose(false);
  }

  return (
    <div>
      <div className="group flex items-start gap-3">
        {editingTitle ? (
          <input
            autoFocus
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            onBlur={saveTitle}
            onKeyDown={(e) => {
              if (e.key === "Enter") saveTitle();
              if (e.key === "Escape") {
                setTitle(chapter.title);
                setEditingTitle(false);
              }
            }}
            className="input-bare font-serif text-4xl sm:text-5xl leading-tight"
          />
        ) : (
          <h1
            className="font-serif text-4xl sm:text-5xl leading-tight cursor-text"
            onClick={() => setEditingTitle(true)}
          >
            {chapter.title}
          </h1>
        )}
        <button
          onClick={() => setEditingTitle((v) => !v)}
          className="opacity-0 group-hover:opacity-100 transition-opacity text-ink-faint hover:text-ink mt-2"
          aria-label="Edit title"
        >
          {editingTitle ? <Check className="h-4 w-4" /> : <Pencil className="h-4 w-4" />}
        </button>
      </div>

      <div className="mt-4 group">
        {editingPurpose ? (
          <textarea
            autoFocus
            value={purpose}
            onChange={(e) => setPurpose(e.target.value)}
            onBlur={savePurpose}
            rows={3}
            className="field font-serif text-lg leading-snug resize-none"
            placeholder="Why this matters."
          />
        ) : chapter.purpose ? (
          <p
            className="font-serif text-lg leading-snug text-ink-secondary max-w-2xl cursor-text"
            onClick={() => setEditingPurpose(true)}
          >
            {chapter.purpose}
          </p>
        ) : (
          <button
            onClick={() => setEditingPurpose(true)}
            className="text-sm text-ink-faint italic hover:text-ink-secondary"
          >
            Add purpose…
          </button>
        )}
      </div>
    </div>
  );
}
