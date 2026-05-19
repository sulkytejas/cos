import Link from "next/link";
import { TypeIcon, typeLabel } from "./TypeIcon";
import { fmtRange, fmtRelative } from "@/lib/utils";
import type { ChapterType, ChapterStatus } from "@/db/schema";

type Props = {
  id: string;
  title: string;
  type: ChapterType;
  status: ChapterStatus;
  startDate: string | null;
  endDate: string | null;
  purpose: string | null;
  todoCount: number;
  todoDone: number;
  progress: number;
  updatedAt: string;
};

export function ChapterCard(props: Props) {
  const pct = Math.round(props.progress * 100);

  return (
    <Link
      href={`/chapter/${props.id}`}
      className="card group block p-5 transition-colors hover:border-warm-strong"
    >
      <div className="flex items-start justify-between gap-3">
        <div className="flex items-center gap-2 text-ink-secondary">
          <TypeIcon type={props.type} />
          <span className="font-mono text-[10px] uppercase tracking-widest text-ink-faint">
            {typeLabel(props.type)}
          </span>
        </div>
        <span className="font-mono text-[10px] uppercase tracking-widest text-ink-faint">
          {fmtRange(props.startDate, props.endDate)}
        </span>
      </div>

      <h3 className="mt-3 font-serif text-2xl leading-tight text-ink">
        {props.title}
      </h3>

      {props.purpose ? (
        <p className="mt-2 line-clamp-2 text-sm text-ink-secondary">
          {props.purpose}
        </p>
      ) : null}

      <div className="mt-5 space-y-2">
        <div className="flex items-baseline justify-between text-xs text-ink-faint font-mono">
          <span>
            {props.todoDone} / {props.todoCount || 0} todos
          </span>
          <span>{pct}%</span>
        </div>
        <div className="h-[3px] w-full overflow-hidden rounded-full bg-[color:var(--color-border-warm)]">
          <div
            className="h-full bg-moss transition-all"
            style={{ width: `${pct}%` }}
          />
        </div>
      </div>

      <div className="mt-4 flex items-center justify-between font-mono text-[10px] uppercase tracking-widest text-ink-faint">
        <span>{props.status}</span>
        <span>updated {fmtRelative(props.updatedAt)}</span>
      </div>
    </Link>
  );
}
