"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";
import { useCapture } from "./CaptureProvider";
import { Plus } from "lucide-react";

const items = [
  { href: "/", label: "Today" },
  { href: "/chapters", label: "Chapters" },
  { href: "/settings", label: "Settings" },
];

export function Nav() {
  const pathname = usePathname();
  const { open } = useCapture();

  return (
    <header className="hairline-b flex items-center justify-between py-5">
      <Link href="/" className="flex items-baseline gap-3">
        <span className="font-serif text-2xl tracking-tight">Atlas</span>
        <span className="font-mono text-[10px] uppercase tracking-widest text-ink-faint">
          v0.1
        </span>
      </Link>

      <nav className="flex items-center gap-1">
        {items.map((item) => {
          const active =
            item.href === "/"
              ? pathname === "/"
              : pathname.startsWith(item.href);
          return (
            <Link
              key={item.href}
              href={item.href}
              className={cn(
                "px-3 py-1.5 text-sm rounded-md transition-colors",
                active
                  ? "text-ink bg-[color:var(--color-border-warm)]"
                  : "text-ink-secondary hover:text-ink hover:bg-[color:var(--color-border-warm)]"
              )}
            >
              {item.label}
            </Link>
          );
        })}
        <button
          onClick={() => open()}
          className="ml-2 btn-ghost hidden sm:inline-flex items-center gap-2"
          aria-label="Open capture"
        >
          <Plus className="h-4 w-4" />
          <span>Capture</span>
          <span className="kbd ml-2">⌘K</span>
        </button>
      </nav>
    </header>
  );
}
