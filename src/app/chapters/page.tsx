"use client";

import { useState } from "react";
import { trpc } from "@/lib/trpc";
import { ChapterCard } from "@/components/ChapterCard";
import { NewChapterModal } from "@/components/NewChapterModal";
import { Plus } from "lucide-react";
import type { ChapterStatus } from "@/db/schema";

const order: ChapterStatus[] = ["active", "upcoming", "paused", "done"];

const groupLabels: Record<ChapterStatus, string> = {
  active: "Active",
  upcoming: "Upcoming",
  paused: "Paused",
  done: "Done",
};

export default function ChaptersPage() {
  const [isOpen, setIsOpen] = useState(false);
  const chaptersQuery = trpc.chapter.list.useQuery();

  const grouped = (chaptersQuery.data ?? []).reduce<
    Record<ChapterStatus, NonNullable<typeof chaptersQuery.data>>
  >(
    (acc, c) => {
      (acc[c.status] ||= []).push(c);
      return acc;
    },
    { active: [], upcoming: [], paused: [], done: [] }
  );

  return (
    <div className="space-y-10 py-6">
      <div className="flex items-end justify-between">
        <div>
          <p className="font-mono text-xs uppercase tracking-widest text-ink-faint">
            All arcs
          </p>
          <h1 className="font-serif text-4xl sm:text-5xl">Chapters</h1>
        </div>
        <button onClick={() => setIsOpen(true)} className="btn-primary">
          <Plus className="h-4 w-4" />
          New chapter
        </button>
      </div>

      {chaptersQuery.isLoading ? (
        <p className="text-ink-faint">Loading…</p>
      ) : null}

      {order.map((status) =>
        grouped[status].length === 0 ? null : (
          <section key={status}>
            <div className="hairline-b flex items-baseline justify-between pb-2 mb-4">
              <h2 className="font-serif text-2xl">{groupLabels[status]}</h2>
              <span className="font-mono text-xs text-ink-faint">
                {grouped[status].length}
              </span>
            </div>
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {grouped[status].map((c) => (
                <ChapterCard key={c.id} {...c} />
              ))}
            </div>
          </section>
        )
      )}

      {isOpen ? <NewChapterModal onClose={() => setIsOpen(false)} /> : null}
    </div>
  );
}
