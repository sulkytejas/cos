"use client";

import { useState } from "react";
import { trpc } from "@/lib/trpc";
import { dueClass, fmtDate, cn } from "@/lib/utils";
import { Calendar, Plus, Trash2 } from "lucide-react";

type Todo = {
  id: string;
  text: string;
  done: boolean;
  dueDate: string | null;
};

type ChapterShape = {
  id: string;
  todos: Todo[];
};

export function TodosTab({ chapter }: { chapter: ChapterShape }) {
  const utils = trpc.useUtils();
  const invalidate = () => {
    utils.chapter.get.invalidate(chapter.id);
    utils.chapter.list.invalidate();
    utils.todo.topAcrossActive.invalidate();
  };

  const create = trpc.todo.create.useMutation({ onSuccess: invalidate });
  const toggle = trpc.todo.toggle.useMutation({ onSuccess: invalidate });
  const update = trpc.todo.update.useMutation({ onSuccess: invalidate });
  const remove = trpc.todo.delete.useMutation({ onSuccess: invalidate });

  const [text, setText] = useState("");
  const [dueDate, setDueDate] = useState("");

  async function add() {
    if (!text.trim()) return;
    await create.mutateAsync({
      chapterId: chapter.id,
      text: text.trim(),
      dueDate: dueDate || null,
    });
    setText("");
    setDueDate("");
  }

  const open = chapter.todos.filter((t) => !t.done);
  const done = chapter.todos.filter((t) => t.done);

  return (
    <div className="space-y-6">
      <div className="card p-4 flex flex-col sm:flex-row gap-3">
        <input
          value={text}
          onChange={(e) => setText(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter") add();
          }}
          placeholder="Add a todo…"
          className="input-bare flex-1"
        />
        <div className="flex items-center gap-2">
          <input
            type="date"
            value={dueDate}
            onChange={(e) => setDueDate(e.target.value)}
            className="field text-sm w-40"
          />
          <button
            onClick={add}
            disabled={!text.trim() || create.isPending}
            className="btn-primary disabled:opacity-40"
          >
            <Plus className="h-4 w-4" />
            Add
          </button>
        </div>
      </div>

      <ul className="card divide-y divide-[color:var(--color-border-warm)]">
        {open.length === 0 ? (
          <li className="px-5 py-6 text-sm text-ink-faint">All clear.</li>
        ) : null}
        {open.map((t) => (
          <TodoRow
            key={t.id}
            todo={t}
            onToggle={(done) => toggle.mutate({ id: t.id, done })}
            onUpdateDate={(d) => update.mutate({ id: t.id, dueDate: d })}
            onDelete={() => remove.mutate(t.id)}
          />
        ))}
      </ul>

      {done.length > 0 ? (
        <details className="group">
          <summary className="font-mono text-[10px] uppercase tracking-widest text-ink-faint cursor-pointer hover:text-ink-secondary">
            Done · {done.length}
          </summary>
          <ul className="mt-3 card divide-y divide-[color:var(--color-border-warm)]">
            {done.map((t) => (
              <TodoRow
                key={t.id}
                todo={t}
                onToggle={(done) => toggle.mutate({ id: t.id, done })}
                onUpdateDate={(d) => update.mutate({ id: t.id, dueDate: d })}
                onDelete={() => remove.mutate(t.id)}
              />
            ))}
          </ul>
        </details>
      ) : null}
    </div>
  );
}

function TodoRow({
  todo,
  onToggle,
  onUpdateDate,
  onDelete,
}: {
  todo: Todo;
  onToggle: (done: boolean) => void;
  onUpdateDate: (date: string | null) => void;
  onDelete: () => void;
}) {
  return (
    <li className="group flex items-start gap-3 px-4 py-3">
      <button
        onClick={() => onToggle(!todo.done)}
        className={cn(
          "mt-0.5 h-4 w-4 shrink-0 rounded-sm border transition-colors flex items-center justify-center",
          todo.done
            ? "bg-moss border-moss"
            : "border-[color:var(--color-border-warm-strong)] hover:border-ink-secondary"
        )}
        aria-label={todo.done ? "Mark as not done" : "Mark as done"}
      >
        {todo.done ? (
          <svg viewBox="0 0 12 12" className="h-3 w-3 text-paper">
            <path
              d="M3 6.5L5 8.5L9 3.5"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.5"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
          </svg>
        ) : null}
      </button>

      <div className="flex-1 min-w-0">
        <p
          className={cn(
            "text-sm leading-snug",
            todo.done ? "text-ink-faint line-through" : "text-ink"
          )}
        >
          {todo.text}
        </p>
        {todo.dueDate ? (
          <p
            className={cn(
              "mt-1 flex items-center gap-1 font-mono text-[11px]",
              dueClass(todo.dueDate)
            )}
          >
            <Calendar className="h-3 w-3" />
            {fmtDate(todo.dueDate)}
          </p>
        ) : null}
      </div>

      <input
        type="date"
        value={todo.dueDate ?? ""}
        onChange={(e) => onUpdateDate(e.target.value || null)}
        className="text-xs text-ink-faint opacity-0 group-hover:opacity-100 transition-opacity bg-transparent border-none w-28"
      />
      <button
        onClick={onDelete}
        className="opacity-0 group-hover:opacity-100 transition-opacity text-ink-faint hover:text-ember"
        aria-label="Delete todo"
      >
        <Trash2 className="h-3.5 w-3.5" />
      </button>
    </li>
  );
}
