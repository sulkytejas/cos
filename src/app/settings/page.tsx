"use client";

import { Mail, Calendar, HardDrive, Plug } from "lucide-react";

const connectors = [
  {
    id: "gmail",
    name: "Gmail",
    icon: Mail,
    description: "Pull travel confirmations, decision threads, and meeting recaps into chapters.",
  },
  {
    id: "calendar",
    name: "Google Calendar",
    icon: Calendar,
    description: "Surface upcoming events on Today. Auto-tag events to the right chapter.",
  },
  {
    id: "drive",
    name: "Google Drive",
    icon: HardDrive,
    description: "Index docs and link them to the chapter they belong to.",
  },
];

export default function SettingsPage() {
  return (
    <div className="space-y-10 py-6">
      <div>
        <p className="font-mono text-xs uppercase tracking-widest text-ink-faint">
          Configuration
        </p>
        <h1 className="font-serif text-4xl sm:text-5xl">Settings</h1>
      </div>

      <section>
        <div className="hairline-b flex items-baseline justify-between pb-2 mb-4">
          <h2 className="font-serif text-2xl">Connectors</h2>
          <span className="font-mono text-xs text-ink-faint">0 of 3 connected</span>
        </div>

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {connectors.map((c) => {
            const Icon = c.icon;
            return (
              <div key={c.id} className="card p-5 space-y-4">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <Icon className="h-4 w-4 text-ink-secondary" />
                    <span className="font-serif text-xl">{c.name}</span>
                  </div>
                  <span className="chip">not connected</span>
                </div>
                <p className="text-sm text-ink-secondary leading-relaxed">
                  {c.description}
                </p>
                <button
                  disabled
                  className="btn-ghost w-full justify-center border border-[color:var(--color-border-warm)] disabled:opacity-60"
                >
                  <Plug className="h-3.5 w-3.5" />
                  Connect (coming soon)
                </button>
              </div>
            );
          })}
        </div>
      </section>

      <section>
        <div className="hairline-b flex items-baseline justify-between pb-2 mb-4">
          <h2 className="font-serif text-2xl">Data</h2>
        </div>
        <div className="card p-5 space-y-2 text-sm text-ink-secondary">
          <p>
            Atlas stores everything locally in{" "}
            <code className="font-mono text-xs text-ink">./data/atlas.db</code>.
            No cloud, no auth, no telemetry.
          </p>
          <p className="font-mono text-xs text-ink-faint">
            To reset, delete the file and restart the dev server. Seed data will
            recreate on next boot.
          </p>
        </div>
      </section>
    </div>
  );
}
