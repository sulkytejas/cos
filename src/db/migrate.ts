import Database from "better-sqlite3";
import { drizzle } from "drizzle-orm/better-sqlite3";
import { migrate } from "drizzle-orm/better-sqlite3/migrator";
import path from "node:path";
import fs from "node:fs";

const DB_DIR = path.join(process.cwd(), "data");
const DB_PATH = path.join(DB_DIR, "atlas.db");
const MIGRATIONS_DIR = path.join(process.cwd(), "drizzle");

if (!fs.existsSync(DB_DIR)) {
  fs.mkdirSync(DB_DIR, { recursive: true });
}

if (!fs.existsSync(MIGRATIONS_DIR)) {
  console.log("[atlas] no migrations directory found, skipping migrate step");
  process.exit(0);
}

const sqlite = new Database(DB_PATH);
sqlite.pragma("journal_mode = WAL");
sqlite.pragma("foreign_keys = ON");

const db = drizzle(sqlite);

try {
  migrate(db, { migrationsFolder: MIGRATIONS_DIR });
  console.log("[atlas] migrations applied");
} catch (err) {
  console.error("[atlas] migration failed:", err);
  process.exit(1);
}

sqlite.close();

import("./seed")
  .then(({ seedIfEmpty }) => seedIfEmpty())
  .then(() => import("./seed-v2").then(({ seedV2IfEmpty }) => seedV2IfEmpty()))
  .catch((err) => {
    console.error("[atlas] seed failed:", err);
  });
