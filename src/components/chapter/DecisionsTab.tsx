"use client";

import { useState } from "react";
import { trpc } from "@/lib/trpc";
import { fmtDate } from "@/lib/utils";
import { Lightbulb, Plus, Loader2, X, Trash2 } from "lucide-react";

type Decision = {
  id: string;
  title: string;
  rationale: string | null;
  optionsConsidered: string | null;
  decidedAt: string;
};

type ChapterShape = {
  id: string;
  decisions: Decision[];
};

export function DecisionsTab({ chapter }: { chapter: ChapterShape }) {
  const [isOpen, setIsOpen] = useState(false);
  const utils = trpc.useUtils();
  const remove = trpc.decision.delete.useMutation({
    onSuccess: () => {
      utils.chapter.get.invalidate(chapter.id);
    },
  });

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <p className="text-sm text-ink-secondary max-w-xl">
          The record of choices. Why you chose this path over the alternatives.
        </p>
        <button onClick={() => setIsOpen(true)} className="btn-primary">
          <Plus className="h-4 w-4" />
          Log decision
        </button>
      </div>

      {chapter.decisions.length === 0 ? (
        <div className="card p-8 text-center">
          <Lightbulb className="h-5 w-5 text-ink-faint mx-auto" />
          <p className="mt-3 text-sm text-ink-secondary">
            No decisions logged yet.
          </p>
        </div>
      ) : (
        <ol className="space-y-4">
          {chapter.decisions.map((d) => (
            <li key={d.id} className="card p-6 group">
              <div className="flex items-start justify-between gap-4">
                <div className="flex-1">
                  <p className="font-mono text-[10px] uppercase tracking-widest text-ink-faint">
                    {fmtDate(d.decidedAt)}
                  </p>
                  <h3 className="mt-1 font-serif text-2xl leading-snug">
                    {d.title}
                  </h3>
                </div>
                <button
                  onClick={() => remove.mutate(d.id)}
                  className="opacity-0 group-hover:opacity-100 transition-opacity text-ink-faint hover:text-ember"
                  aria-label="Delete decision"
                >
                  <Trash2 className="h-3.5 w-3.5" />
                </button>
              </div>

              {d.rationale ? (
                <p className="mt-3 text-sm leading-relaxed text-ink-secondary whitespace-pre-wrap">
                  {d.rationale}
                </p>
              ) : null}

              {d.optionsConsidered ? (
                <div className="mt-4 hairline-t pt-3">
                  <p className="font-mono text-[10px] uppercase tracking-widest text-ink-faint">
                    Options considered
                  </p>
                  <p className="mt-2 text-xs leading-relaxed text-ink-secondary whitespace-pre-wrap font-mono">
                    {d.optionsConsidered}
                  </p>
                </div>
              ) : null}
            </li>
          ))}
        </ol>
      )}

      {isOpen ? (
        <DecisionModal chapterId={chapter.id} onClose={() => setIsOpen(false)} />
      ) : null}
    </div>
  );
}

function DecisionModal({
  chapterId,
  onClose,
}: {
  chapterId: string;
  onClose: () => void;
}) {
  const utils = trpc.useUtils();
  const create = trpc.decision.create.useMutation({
    onSuccess: () => utils.chapter.get.invalidate(chapterId),
  });

  const [title, setTitle] = useState("");
  const [rationale, setRationale] = useState("");
  const [optionsConsidered, setOptions] = useState("");
  const [decidedAt, setDecidedAt] = useState(
    new Date().toISOString().slice(0, 10)
  );

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!title.trim()) return;
    await create.mutateAsync({
      chapterId,
      title: title.trim(),
      rationale: rationale.trim() || null,
      optionsConsidered: optionsConsidered.trim() || null,
      decidedAt: new Date(decidedAt).toISOString(),
    });
    onClose();
  }

  return (
    <div
      className="fixed inset-0 z-40 flex items-start justify-center bg-[rgba(26,24,20,0.35)] px-4 pt-[10vh]"
      onClick={onClose}
    >
      <form
        onSubmit={submit}
        onClick={(e) => e.stopPropagation()}
        className="card fade-in w-full max-w-xl overflow-hidden"
      >
        <div className="hairline-b flex items-center justify-between px-5 py-3">
          <span className="font-mono text-xs uppercase tracking-widest text-ink-faint">
            Log decision
          </span>
          <button type="button" onClick={onClose} className="text-ink-faint hover:text-ink">
            <X className="h-4 w-4" />
          </button>
        </div>

        <div className="space-y-5 px-5 py-5">
          <div>
            <label className="font-mono text-[10px] uppercase tracking-widest text-ink-faint">
              Title
            </label>
            <input
              autoFocus
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="What did you decide?"
              className="input-line mt-1 font-serif text-xl"
            />
          </div>

          <div>
            <label className="font-mono text-[10px] uppercase tracking-widest text-ink-faint">
              Rationale
            </label>
            <textarea
              value={rationale}
              onChange={(e) => setRationale(e.target.value)}
              rows={4}
              placeholder="Why this path."
              className="field mt-1 resize-none"
            />
          </div>

          <div>
            <label className="font-mono text-[10px] uppercase tracking-widest text-ink-faint">
              Options considered
            </label>
            <textarea
              value={optionsConsidered}
              onChange={(e) => setOptions(e.target.value)}
              rows={4}
              placeholder="The alternatives, briefly."
              className="field mt-1 resize-none font-mono text-xs"
            />
          </div>

          <div>
            <label className="font-mono text-[10px] uppercase tracking-widest text-ink-faint">
              Decided at
            </label>
            <input
              type="date"
              value={decidedAt}
              onChange={(e) => setDecidedAt(e.target.value)}
              className="field mt-1 font-mono text-sm w-48"
            />
          </div>
        </div>

        <div className="hairline-t flex items-center justify-end gap-2 px-5 py-3">
          <button type="button" onClick={onClose} className="btn-ghost">
            Cancel
          </button>
          <button
            type="submit"
            disabled={create.isPending || !title.trim()}
            className="btn-primary disabled:opacity-40"
          >
            {create.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : null}
            Log
          </button>
        </div>
      </form>
    </div>
  );
}
