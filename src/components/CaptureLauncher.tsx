"use client";

import { useCapture } from "./CaptureProvider";
import { CaptureModal } from "./CaptureModal";
import { Plus } from "lucide-react";

export function CaptureLauncher() {
  const { isOpen, open } = useCapture();

  return (
    <>
      <button
        onClick={() => open()}
        className="sm:hidden fixed bottom-6 right-6 z-30 h-14 w-14 rounded-full bg-moss text-paper shadow-[0_4px_24px_-6px_rgba(45,74,58,0.45)] flex items-center justify-center transition-transform active:scale-95"
        style={{ color: "var(--color-paper)" }}
        aria-label="Quick capture"
      >
        <Plus className="h-6 w-6" />
      </button>
      {isOpen && <CaptureModal />}
    </>
  );
}
