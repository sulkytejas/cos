/**
 * Per-user/day token budget — the durable side of the gateway's spend ceiling
 * (SERVER_ARCHITECTURE.md §4.b). Persisted in the `usage_ledger` table so the
 * budget survives a worker restart.
 *
 * The budget counts `input + cache_creation + output` ONLY; free
 * `cache_read_input_tokens` are tracked for observability but excluded from the
 * cap (porting the iOS number while fixing its accounting).
 *
 * This module owns a dedicated better-sqlite3 handle on the same atlas.db file
 * the web app and worker share, with busy_timeout set (§4.c) so it never throws
 * SQLITE_BUSY when it contends the WAL with the other two handles. Keeping the
 * handle local avoids coupling the gateway (web tree) to worker/src/db.
 */
import Database from "better-sqlite3";
import { randomUUID } from "node:crypto";
import path from "node:path";
import fs from "node:fs";
import { PER_USER_DAILY_TOKEN_CAP } from "./config";
import type { ChargeableUsage } from "./buckets";

/** Resolve the shared atlas.db path the same way src/db/client.ts does. */
function resolveDbPath(): string {
  // ATLAS_DB_PATH lets the operator point all handles at /opt/atlas/data/atlas.db.
  const override = process.env.ATLAS_DB_PATH;
  if (override) return override;
  const dir = path.join(process.cwd(), "data");
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  return path.join(dir, "atlas.db");
}

const globalForLedger = globalThis as unknown as { __ledgerDb?: Database.Database };

function getDb(): Database.Database {
  if (globalForLedger.__ledgerDb) return globalForLedger.__ledgerDb;
  const sqlite = new Database(resolveDbPath());
  sqlite.pragma("journal_mode = WAL");
  sqlite.pragma("foreign_keys = ON");
  // Required (§4.c): without this, contending the WAL throws SQLITE_BUSY immediately.
  sqlite.pragma("busy_timeout = 5000");
  globalForLedger.__ledgerDb = sqlite;
  return sqlite;
}

/** Local `YYYY-MM-DD` day key for budgeting. */
function today(): string {
  const d = new Date();
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

/**
 * Charge a completed call against the user's daily ledger. Idempotency is not
 * attempted here (a call is charged once, after it succeeds); the gateway calls
 * this exactly once per successful response. Atomic UPSERT keyed by (userId, day).
 */
export function chargeUsageLedger(userId: string, usage: ChargeableUsage): void {
  const db = getDb();
  const input = usage.input_tokens ?? 0;
  const cacheCreation = usage.cache_creation_input_tokens ?? 0;
  const cacheRead = usage.cache_read_input_tokens ?? 0;
  const output = usage.output_tokens ?? 0;
  // Budget counts input + cache_creation + output; cache_read is FREE.
  const chargeable = input + cacheCreation + output;
  const now = new Date().toISOString();
  const day = today();

  db.prepare(
    `INSERT INTO usage_ledger
       (id, user_id, day, chargeable_tokens, input_tokens, cache_creation_tokens,
        cache_read_tokens, output_tokens, requests, created_at, updated_at)
     VALUES
       (@id, @userId, @day, @chargeable, @input, @cacheCreation,
        @cacheRead, @output, 1, @now, @now)
     ON CONFLICT(user_id, day) DO UPDATE SET
       chargeable_tokens     = chargeable_tokens     + @chargeable,
       input_tokens          = input_tokens          + @input,
       cache_creation_tokens = cache_creation_tokens + @cacheCreation,
       cache_read_tokens     = cache_read_tokens     + @cacheRead,
       output_tokens         = output_tokens         + @output,
       requests              = requests              + 1,
       updated_at            = @now`,
  ).run({
    id: randomUUID(),
    userId,
    day,
    chargeable,
    input,
    cacheCreation,
    cacheRead,
    output,
    now,
  });
}

/** Chargeable tokens spent by `userId` today. */
export function getDailySpend(userId: string): number {
  const db = getDb();
  const row = db
    .prepare(`SELECT chargeable_tokens AS spent FROM usage_ledger WHERE user_id = ? AND day = ?`)
    .get(userId, today()) as { spent?: number } | undefined;
  return row?.spent ?? 0;
}

/** True once the user has hit their daily cap — callers should refuse new work. */
export function isOverDailyBudget(userId: string): boolean {
  return getDailySpend(userId) >= PER_USER_DAILY_TOKEN_CAP;
}

/** Remaining chargeable tokens before the cap (for a server-reported readout). */
export function remainingDailyBudget(userId: string): number {
  return Math.max(0, PER_USER_DAILY_TOKEN_CAP - getDailySpend(userId));
}
