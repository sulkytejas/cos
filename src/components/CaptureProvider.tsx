"use client";

import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from "react";

type CaptureContextValue = {
  isOpen: boolean;
  open: (chapterId?: string) => void;
  close: () => void;
  preselectedChapterId: string | null;
};

const CaptureContext = createContext<CaptureContextValue | null>(null);

export function CaptureProvider({ children }: { children: ReactNode }) {
  const [isOpen, setIsOpen] = useState(false);
  const [preselectedChapterId, setPreselected] = useState<string | null>(null);

  const open = useCallback((chapterId?: string) => {
    setPreselected(chapterId ?? null);
    setIsOpen(true);
  }, []);

  const close = useCallback(() => {
    setIsOpen(false);
    setPreselected(null);
  }, []);

  useEffect(() => {
    function handler(e: KeyboardEvent) {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        setIsOpen((v) => !v);
      } else if (e.key === "Escape") {
        setIsOpen(false);
      }
    }
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, []);

  return (
    <CaptureContext.Provider value={{ isOpen, open, close, preselectedChapterId }}>
      {children}
    </CaptureContext.Provider>
  );
}

export function useCapture() {
  const ctx = useContext(CaptureContext);
  if (!ctx) throw new Error("useCapture must be used within CaptureProvider");
  return ctx;
}
