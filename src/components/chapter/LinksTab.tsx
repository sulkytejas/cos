"use client";

import { useState } from "react";
import Link from "next/link";
import { trpc } from "@/lib/trpc";
import { TypeIcon } from "@/components/TypeIcon";
import { linkRelations, type LinkRelation, type ChapterType, type ChapterStatus } from "@/db/schema";
import { ArrowRight, ArrowLeft, Plus, Loader2, X, Trash2 } from "lucide-react";

type LinkRow = {
  fromId: string;
  toId: string;
  relation: LinkRelation;
  note: string | null;
  direction: "outgoing" | "incoming";
  other: {
    id: string;
    title: string;
    type: ChapterType;
    status: ChapterStatus;
  } | undefined;
};

type ChapterShape = {
  id: string;
  links: LinkRow[];
};

const relationLabels: Record<LinkRelation, string> = {
  blocks: "blocks",
  enables: "enables",
  conflicts: "conflicts with",
  related: "related to",
};

const relationToneClass: Record<LinkRelation, string> = {
  blocks: "chip-ember",
  enables: "chip-moss",
  conflicts: "chip-ember",
  related: "",
};

export function LinksTab({ chapter }: { chapter: ChapterShape }) {
  const [isOpen, setIsOpen] = useState(false);
  const utils = trpc.useUtils();
  const unlink = trpc.chapter.unlink.useMutation({
    onSuccess: () => utils.chapter.get.invalidate(chapter.id),
  });

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <p className="text-sm text-ink-secondary max-w-xl">
          How this chapter relates to the others. Blocks, enables, conflicts with, or simply touches.
        </p>
        <button onClick={() => setIsOpen(true)} className="btn-primary">
          <Plus className="h-4 w-4" />
          Add link
        </button>
      </div>

      {chapter.links.length === 0 ? (
        <div className="card p-8 text-center">
          <p className="text-sm text-ink-faint">No links yet.</p>
        </div>
      ) : (
        <ul className="card divide-y divide-[color:var(--color-border-warm)]">
          {chapter.links.map((l) =>
            !l.other ? null : (
              <li
                key={`${l.fromId}-${l.toId}-${l.relation}`}
                className="group flex items-center gap-4 px-5 py-4"
              >
                <span className={`chip ${relationToneClass[l.relation]}`}>
                  {relationLabels[l.relation]}
                </span>
                {l.direction === "outgoing" ? (
                  <ArrowRight className="h-3.5 w-3.5 text-ink-faint" />
                ) : (
                  <ArrowLeft className="h-3.5 w-3.5 text-ink-faint" />
                )}
                <Link
                  href={`/chapter/${l.other.id}`}
                  className="flex items-center gap-2 hover:text-moss"
                >
                  <TypeIcon type={l.other.type} className="h-3.5 w-3.5" />
                  <span className="text-sm">{l.other.title}</span>
                </Link>
                {l.note ? (
                  <span className="text-xs text-ink-secondary italic ml-auto pr-4 max-w-md truncate">
                    “{l.note}”
                  </span>
                ) : null}
                <button
                  onClick={() =>
                    unlink.mutate({
                      fromId: l.fromId,
                      toId: l.toId,
                      relation: l.relation,
                    })
                  }
                  className="ml-auto opacity-0 group-hover:opacity-100 text-ink-faint hover:text-ember"
                  aria-label="Remove link"
                >
                  <Trash2 className="h-3.5 w-3.5" />
                </button>
              </li>
            )
          )}
        </ul>
      )}

      {isOpen ? (
        <NewLinkModal chapterId={chapter.id} onClose={() => setIsOpen(false)} />
      ) : null}
    </div>
  );
}

function NewLinkModal({
  chapterId,
  onClose,
}: {
  chapterId: string;
  onClose: () => void;
}) {
  const utils = trpc.useUtils();
  const chaptersQuery = trpc.chapter.list.useQuery();
  const link = trpc.chapter.link.useMutation({
    onSuccess: () => utils.chapter.get.invalidate(chapterId),
  });

  const [toId, setToId] = useState("");
  const [relation, setRelation] = useState<LinkRelation>("related");
  const [note, setNote] = useState("");

  const options =
    chaptersQuery.data?.filter((c) => c.id !== chapterId) ?? [];

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!toId) return;
    await link.mutateAsync({
      fromId: chapterId,
      toId,
      relation,
      note: note.trim() || null,
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
        className="card fade-in w-full max-w-lg overflow-hidden"
      >
        <div className="hairline-b flex items-center justify-between px-5 py-3">
          <span className="font-mono text-xs uppercase tracking-widest text-ink-faint">
            Link chapter
          </span>
          <button type="button" onClick={onClose} className="text-ink-faint hover:text-ink">
            <X className="h-4 w-4" />
          </button>
        </div>

        <div className="space-y-5 px-5 py-5">
          <div>
            <label className="font-mono text-[10px] uppercase tracking-widest text-ink-faint">
              Relation
            </label>
            <select
              value={relation}
              onChange={(e) => setRelation(e.target.value as LinkRelation)}
              className="field mt-1"
            >
              {linkRelations.map((r) => (
                <option key={r} value={r}>
                  {relationLabels[r]}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className="font-mono text-[10px] uppercase tracking-widest text-ink-faint">
              Target chapter
            </label>
            <select
              value={toId}
              onChange={(e) => setToId(e.target.value)}
              className="field mt-1"
            >
              <option value="">— select —</option>
              {options.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.title}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className="font-mono text-[10px] uppercase tracking-widest text-ink-faint">
              Note (optional)
            </label>
            <input
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="A short note about this link."
              className="field mt-1"
            />
          </div>
        </div>

        <div className="hairline-t flex items-center justify-end gap-2 px-5 py-3">
          <button type="button" onClick={onClose} className="btn-ghost">
            Cancel
          </button>
          <button
            type="submit"
            disabled={!toId || link.isPending}
            className="btn-primary disabled:opacity-40"
          >
            {link.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : null}
            Link
          </button>
        </div>
      </form>
    </div>
  );
}
