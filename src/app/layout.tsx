import type { Metadata } from "next";
import "./globals.css";
import { Providers } from "./providers";
import { Nav } from "@/components/Nav";
import { CaptureLauncher } from "@/components/CaptureLauncher";

export const metadata: Metadata = {
  title: "Atlas",
  description: "A personal life assistant",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="" />
        <link
          href="https://fonts.googleapis.com/css2?family=Instrument+Serif:ital@0;1&family=Manrope:wght@300;400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap"
          rel="stylesheet"
        />
      </head>
      <body className="min-h-screen bg-paper text-ink">
        <Providers>
          <div className="mx-auto flex min-h-screen max-w-6xl flex-col px-4 pb-24 sm:px-8 lg:px-12">
            <Nav />
            <main className="flex-1 pt-4">{children}</main>
            <footer className="hairline-t mt-16 pt-6 text-xs text-ink-faint font-mono">
              atlas · local · {new Date().getFullYear()}
            </footer>
          </div>
          <CaptureLauncher />
        </Providers>
      </body>
    </html>
  );
}
