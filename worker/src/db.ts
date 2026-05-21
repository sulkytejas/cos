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

export const db = drizzle(sqlite, { schema });
export { schema };
