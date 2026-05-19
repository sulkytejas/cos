"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { trpc } from "@/lib/trpc";
import { chapterTypes, chapterStatuses } from "@/db/schema";
import type { ChapterType, ChapterStatus } from "@/db/schema";
import { X, Loader2 } from "lucide-react";

export function NewChapterModal({ onClose }: { onClose: () => void }) {
  const router = useRouter();
  const utils = trpc.useUtils();
  const create = trpc.chapter.create.useMutation();

  const [title, setTitle] = useState("");
  const [type, setType] = useState<ChapterType>("project");
  const [status, setStatus] = useState<ChapterStatus>("active");
  const [startDate, setStartDate] = useState("");
  const [endDate, setEndDate] = useState("");
  const [purpose, setPurpose] = useState("");

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!title.trim()) return;
    const res = await create.mutateAsync({
      title: title.trim(),
      type,
      status,
      startDate: startDate || null,
      endDate: endDate || null,
      purpose: purpose.trim() || null,
    });
    await utils.chapter.list.invalidate();
    onClose();
    router.push(`/chapter/${res.id}`);
  }

  return (
    <div
      className="fixed inset-0 z-40 flex items-start justify-center bg-[rgba(26,24,20,0.35)] px-4 pt-[10vh]"
      onClick={onClose}
    >
      <form
        onSubmit={submit}
        onClick={(e) => e.stopPropagation()}
        className="card fade-in w-full max-w-lg overflow-hidden"
      >
        <div className="hairline-b flex items-center justify-between px-5 py-3">
          <span className="font-mono text-xs uppercase tracking-widest text-ink-faint">
            New chapter
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
              placeholder="e.g. Trip to Ladakh"
              className="input-line mt-1 font-serif text-xl"
            />
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="font-mono text-[10px] uppercase tracking-widest text-ink-faint">
                Type
              </label>
              <select
                value={type}
                onChange={(e) => setType(e.target.value as ChapterType)}
                className="field mt-1"
              >
                {chapterTypes.map((t) => (
                  <option key={t} value={t}>
                    {t}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label className="font-mono text-[10px] uppercase tracking-widest text-ink-faint">
                Status
              </label>
              <select
                value={status}
                onChange={(e) => setStatus(e.target.value as ChapterStatus)}
                className="field mt-1"
              >
                {chapterStatuses.map((s) => (
                  <option key={s} value={s}>
                    {s}
                  </option>
                ))}
              </select>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="font-mono text-[10px] uppercase tracking-widest text-ink-faint">
                Start
              </label>
              <input
                type="date"
                value={startDate}
                onChange={(e) => setStartDate(e.target.value)}
                className="field mt-1 font-mono text-sm"
              />
            </div>
            <div>
              <label className="font-mono text-[10px] uppercase tracking-widest text-ink-faint">
                End
              </label>
              <input
                type="date"
                value={endDate}
                onChange={(e) => setEndDate(e.target.value)}
                className="field mt-1 font-mono text-sm"
              />
            </div>
          </div>

          <div>
            <label className="font-mono text-[10px] uppercase tracking-widest text-ink-faint">
              Purpose
            </label>
            <textarea
              value={purpose}
              onChange={(e) => setPurpose(e.target.value)}
              rows={3}
              placeholder="Why this matters."
              className="field mt-1 resize-none"
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
            Create
          </button>
        </div>
      </form>
    </div>
  );
}
