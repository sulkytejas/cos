"use client";

import Link from "next/link";
import { trpc } from "@/lib/trpc";
import { TypeIcon } from "@/components/TypeIcon";
import { dueClass, fmtDate, fmtRelative } from "@/lib/utils";
import { differenceInCalendarDays, format, parseISO } from "date-fns";
import { ArrowUpRight, Calendar, Clock } from "lucide-react";

export default function TodayPage() {
  const today = new Date();
  const chaptersQuery = trpc.chapter.list.useQuery();
  const todosQuery = trpc.todo.topAcrossActive.useQuery({ limit: 5 });

  const upcomingMilestone = computeNextMilestone(chaptersQuery.data ?? []);
  const activeCount =
    chaptersQuery.data?.filter((c) => c.status === "active").length ?? 0;
  const upcomingCount =
    chaptersQuery.data?.filter((c) => c.status === "upcoming").length ?? 0;

  return (
    <div className="space-y-10">
      <section className="flex flex-col gap-2 pt-6 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="font-mono text-xs uppercase tracking-widest text-ink-faint">
            {format(today, "EEEE")}
          </p>
          <h1 className="font-serif text-5xl leading-none sm:text-6xl">
            {format(today, "MMMM d")}
          </h1>
        </div>
        {upcomingMilestone ? (
          <div className="text-right">
            <p className="font-mono text-[10px] uppercase tracking-widest text-ink-faint">
              next milestone
            </p>
            <p className="font-serif text-xl">
              {upcomingMilestone.days === 0
                ? "today"
                : upcomingMilestone.days > 0
                  ? `T-${upcomingMilestone.days}d`
                  : `+${Math.abs(upcomingMilestone.days)}d`}{" "}
              <span className="text-ink-secondary text-base">
                · {upcomingMilestone.title}
              </span>
            </p>
          </div>
        ) : null}
      </section>

      <section className="grid grid-cols-1 gap-6 lg:grid-cols-3">
        <div className="card lg:col-span-2 p-7">
          <div className="flex items-center justify-between">
            <span className="font-mono text-[10px] uppercase tracking-widest text-ink-faint">
              Morning brief
            </span>
            <span className="font-mono text-[10px] uppercase tracking-widest text-ink-faint">
              {format(today, "yyyy-MM-dd")}
            </span>
          </div>
          <p className="mt-5 font-serif text-2xl leading-snug text-ink">
            {brief(chaptersQuery.data ?? [], activeCount, upcomingCount)}
          </p>
          <p className="mt-5 text-sm text-ink-secondary leading-relaxed">
            Synthesis is placeholder for now — the model layer plugs in here. The
            shape is right: a few sentences pulled from across active chapters,
            surfaced where you start the day. Tomorrow it can read the journal,
            the decision log, the email feed — and read them back to you here.
          </p>
        </div>

        <div className="card p-6">
          <div className="flex items-center justify-between">
            <span className="font-mono text-[10px] uppercase tracking-widest text-ink-faint">
              Today's calendar
            </span>
            <Calendar className="h-3.5 w-3.5 text-ink-faint" />
          </div>
          <ul className="mt-4 space-y-3 text-sm">
            {fakeCalendar.map((ev) => (
              <li key={ev.time} className="flex items-start gap-3">
                <span className="font-mono text-xs text-ink-faint w-12 shrink-0 pt-0.5">
                  {ev.time}
                </span>
                <div>
                  <p className="text-ink">{ev.title}</p>
                  <p className="text-xs text-ink-faint">{ev.subtitle}</p>
                </div>
              </li>
            ))}
          </ul>
          <p className="mt-5 hairline-t pt-3 font-mono text-[10px] uppercase tracking-widest text-ink-faint">
            placeholder · connect Calendar in Settings
          </p>
        </div>
      </section>

      <section>
        <div className="flex items-baseline justify-between">
          <h2 className="font-serif text-2xl">Up next</h2>
          <Link
            href="/chapters"
            className="btn-ghost text-xs font-mono uppercase tracking-widest"
          >
            All chapters <ArrowUpRight className="h-3 w-3" />
          </Link>
        </div>

        <ul className="mt-4 card divide-y divide-[color:var(--color-border-warm)]">
          {todosQuery.data?.length === 0 ? (
            <li className="px-5 py-6 text-sm text-ink-secondary">
              No active todos. Capture something with{" "}
              <span className="kbd">⌘K</span>.
            </li>
          ) : null}
          {todosQuery.data?.map((t) => (
            <li
              key={t.id}
              className="flex items-start gap-4 px-5 py-4 transition-colors hover:bg-[color:var(--color-paper)]"
            >
              <div className="mt-1 h-3.5 w-3.5 shrink-0 rounded-sm border border-[color:var(--color-border-warm-strong)]" />
              <div className="flex-1 min-w-0">
                <p className="text-sm text-ink leading-snug">{t.text}</p>
                <div className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-[11px] text-ink-faint">
                  <Link
                    href={`/chapter/${t.chapterId}`}
                    className="flex items-center gap-1.5 hover:text-ink"
                  >
                    <TypeIcon
                      type={t.chapterType}
                      className="h-3 w-3"
                    />
                    <span>{t.chapterTitle}</span>
                  </Link>
                  {t.dueDate ? (
                    <span
                      className={`flex items-center gap-1 font-mono ${dueClass(t.dueDate)}`}
                    >
                      <Clock className="h-3 w-3" />
                      {fmtDate(t.dueDate)}
                    </span>
                  ) : null}
                </div>
              </div>
            </li>
          ))}
        </ul>
      </section>

      <section>
        <div className="flex items-baseline justify-between">
          <h2 className="font-serif text-2xl">Active chapters</h2>
          <span className="font-mono text-xs text-ink-faint">
            {activeCount} active · {upcomingCount} upcoming
          </span>
        </div>
        <ul className="mt-4 grid grid-cols-1 gap-3 sm:grid-cols-2">
          {chaptersQuery.data
            ?.filter((c) => c.status === "active" || c.status === "upcoming")
            .map((c) => (
              <li key={c.id}>
                <Link
                  href={`/chapter/${c.id}`}
                  className="card flex items-center justify-between gap-4 p-4 transition-colors hover:border-warm-strong"
                >
                  <div className="flex items-center gap-3 min-w-0">
                    <TypeIcon type={c.type} className="h-4 w-4 text-ink-secondary" />
                    <div className="min-w-0">
                      <p className="truncate text-sm text-ink">{c.title}</p>
                      <p className="font-mono text-[10px] uppercase tracking-widest text-ink-faint">
                        {c.status} · updated {fmtRelative(c.updatedAt)}
                      </p>
                    </div>
                  </div>
                  <span className="font-mono text-xs text-ink-faint">
                    {c.todoDone}/{c.todoCount}
                  </span>
                </Link>
              </li>
            ))}
        </ul>
      </section>
    </div>
  );
}

const fakeCalendar = [
  { time: "09:00", title: "Deep work block", subtitle: "Deck v3, slides 1–6" },
  { time: "11:30", title: "Lightspeed — partner intro", subtitle: "30 min · video" },
  { time: "15:00", title: "Tennis", subtitle: "Bombay Gymkhana" },
  { time: "19:30", title: "Dinner — A.", subtitle: "Soam, Babulnath" },
];

function computeNextMilestone(
  chapters: Array<{ title: string; startDate: string | null; endDate: string | null; status: string }>
) {
  const now = new Date();
  const candidates: { title: string; days: number }[] = [];

  for (const c of chapters) {
    if (c.status === "done") continue;
    if (c.startDate) {
      try {
        const d = parseISO(c.startDate);
        const diff = differenceInCalendarDays(d, now);
        if (diff >= -7) {
          candidates.push({ title: `${c.title} begins`, days: diff });
        }
      } catch {}
    }
    if (c.endDate) {
      try {
        const d = parseISO(c.endDate);
        const diff = differenceInCalendarDays(d, now);
        if (diff >= 0 && diff <= 365) {
          candidates.push({ title: `${c.title} ends`, days: diff });
        }
      } catch {}
    }
  }

  if (candidates.length === 0) return null;
  candidates.sort((a, b) => Math.abs(a.days) - Math.abs(b.days));
  return candidates[0];
}

function brief(
  chapters: Array<{ title: string; status: string; type: string }>,
  active: number,
  upcoming: number
): string {
  if (chapters.length === 0) {
    return "Quiet board. Create a chapter to give the day a shape.";
  }
  const activeTitles = chapters
    .filter((c) => c.status === "active")
    .map((c) => c.title);
  const upcomingTitles = chapters
    .filter((c) => c.status === "upcoming")
    .map((c) => c.title);

  const parts: string[] = [];
  if (active > 0) {
    parts.push(
      `${active} chapter${active === 1 ? "" : "s"} in motion — ${activeTitles.slice(0, 2).join(", ")}${activeTitles.length > 2 ? `, and ${activeTitles.length - 2} more` : ""}.`
    );
  }
  if (upcoming > 0) {
    parts.push(
      `On the horizon: ${upcomingTitles.slice(0, 2).join(", ")}.`
    );
  }
  parts.push("Hold the arc, not just the items.");
  return parts.join(" ");
}
