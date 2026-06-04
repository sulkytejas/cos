/**
 * Worker DB client — same SQLite file as the web app. We open it as a
 * separate handle here because the worker is a separate Node process.
 * Drizzle's better-sqlite3 driver is sync and fast enough for our scale.
 */
import Database from "better-sqlite3";
import { drizzle } from "drizzle-orm/better-sqlite3";
import path from "node:path";
import fs from "node:fs";
import { fileURLToPath } from "node:url";
import * as schema from "../../src/db/schema";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
// Anchor at repo root regardless of where we're launched from.
const REPO_ROOT = path.resolve(__dirname, "..", "..");
const DB_DIR = path.join(REPO_ROOT, "data");
const DB_PATH = path.join(DB_DIR, "atlas.db");

if (!fs.existsSync(DB_DIR)) {
  fs.mkdirSync(DB_DIR, { recursive: true });
}

const sqlite = new Database(DB_PATH);
sqlite.pragma("journal_mode = WAL");
sqlite.pragma("foreign_keys = ON");
// SERVER_ARCHITECTURE.md §4.c — required: the worker and the Next.js API both
// contend the WAL; without busy_timeout better-sqlite3 throws SQLITE_BUSY
// immediately on a writer collision instead of waiting briefly.
sqlite.pragma("busy_timeout = 5000");

export const db = drizzle(sqlite, { schema });
// The raw better-sqlite3 handle. The queue needs it for the atomic
// `UPDATE … RETURNING` claim, `INSERT … ON CONFLICT` enqueue-dedup, and the
// single-statement recovery txn — patterns Drizzle's query builder doesn't
// express directly. Reuses the same connection (pragmas, WAL, busy_timeout).
export const sqlite_ = sqlite;
export { schema };
