"use client";

import { use, useState } from "react";
import Link from "next/link";
import { trpc } from "@/lib/trpc";
import { fmtRange } from "@/lib/utils";
import { TypeIcon, typeLabel } from "@/components/TypeIcon";
import { ChapterHeader } from "@/components/chapter/ChapterHeader";
import { TodosTab } from "@/components/chapter/TodosTab";
import { DecisionsTab } from "@/components/chapter/DecisionsTab";
import { JournalTab } from "@/components/chapter/JournalTab";
import { LinksTab } from "@/components/chapter/LinksTab";
import { cn } from "@/lib/utils";

type Tab = "todos" | "decisions" | "journal" | "links";

const tabs: { id: Tab; label: string }[] = [
  { id: "todos", label: "Todos" },
  { id: "decisions", label: "Decisions" },
  { id: "journal", label: "Journal" },
  { id: "links", label: "Links" },
];

export default function ChapterDetail({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = use(params);
  const [tab, setTab] = useState<Tab>("todos");
  const chapterQuery = trpc.chapter.get.useQuery(id);

  if (chapterQuery.isLoading) {
    return <p className="pt-12 text-ink-faint">Loading…</p>;
  }
  if (!chapterQuery.data) {
    return (
      <div className="pt-12">
        <p className="text-ink-secondary">Chapter not found.</p>
        <Link href="/chapters" className="btn-ghost mt-4">
          ← All chapters
        </Link>
      </div>
    );
  }

  const c = chapterQuery.data;

  return (
    <div className="pb-12 pt-6 space-y-8">
      <div>
        <Link
          href="/chapters"
          className="font-mono text-[10px] uppercase tracking-widest text-ink-faint hover:text-ink"
        >
          ← Chapters
        </Link>
        <div className="mt-3 flex items-center gap-2 text-ink-secondary">
          <TypeIcon type={c.type} />
          <span className="font-mono text-[10px] uppercase tracking-widest text-ink-faint">
            {typeLabel(c.type)} · {c.status} · {fmtRange(c.startDate, c.endDate)}
          </span>
        </div>
      </div>

      <ChapterHeader chapter={c} />

      <div className="hairline-b flex gap-1 overflow-x-auto">
        {tabs.map((t) => {
          const counts: Record<Tab, number> = {
            todos: c.todos.length,
            decisions: c.decisions.length,
            journal: c.entries.length,
            links: c.links.length,
          };
          return (
            <button
              key={t.id}
              onClick={() => setTab(t.id)}
              className={cn(
                "relative px-4 py-3 text-sm transition-colors",
                tab === t.id
                  ? "text-ink"
                  : "text-ink-faint hover:text-ink-secondary"
              )}
            >
              <span>{t.label}</span>
              <span className="ml-2 font-mono text-[10px] text-ink-faint">
                {counts[t.id]}
              </span>
              {tab === t.id ? (
                <span className="absolute inset-x-3 -bottom-px h-px bg-ink" />
              ) : null}
            </button>
          );
        })}
      </div>

      <div>
        {tab === "todos" && <TodosTab chapter={c} />}
        {tab === "decisions" && <DecisionsTab chapter={c} />}
        {tab === "journal" && <JournalTab chapter={c} />}
        {tab === "links" && <LinksTab chapter={c} />}
      </div>
    </div>
  );
}
