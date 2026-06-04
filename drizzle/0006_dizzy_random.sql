-- P2 scope (SERVER_ARCHITECTURE.md §4.d/§4.f): ONE migration adds userId +
-- updatedAt + deletedAt (and a per-user index) to every user-owned table.
--
-- SQLite cannot `ALTER TABLE … ADD COLUMN … DEFAULT (current_timestamp)` (a
-- non-constant default is rejected on a populated table) and cannot ADD a
-- NOT NULL column with no default to a populated table. So each `updated_at`
-- column is added with a CONSTANT sentinel default to satisfy the backfill,
-- then normalized per-row to that table's existing create-time value (ISO-8601
-- UTC) so a cursor-by-`updatedAt` sync is monotonic from day one. New-row
-- inserts set `updated_at` explicitly (routers, worker) or via the schema's
-- `$defaultFn` (seeds / any omitting insert) — never the sentinel.

-- ─────────────────────────── briefs ───────────────────────────
ALTER TABLE `briefs` ADD `user_id` text DEFAULT 'atlas-operator' NOT NULL;--> statement-breakpoint
ALTER TABLE `briefs` ADD `updated_at` text DEFAULT '1970-01-01T00:00:00.000Z' NOT NULL;--> statement-breakpoint
ALTER TABLE `briefs` ADD `deleted_at` text;--> statement-breakpoint
UPDATE `briefs` SET `updated_at` = `created_at` WHERE `updated_at` = '1970-01-01T00:00:00.000Z';--> statement-breakpoint
CREATE INDEX `briefs_user_idx` ON `briefs` (`user_id`);--> statement-breakpoint

-- ─────────────────────────── chapter_links ───────────────────────────
ALTER TABLE `chapter_links` ADD `user_id` text DEFAULT 'atlas-operator' NOT NULL;--> statement-breakpoint
ALTER TABLE `chapter_links` ADD `updated_at` text DEFAULT '1970-01-01T00:00:00.000Z' NOT NULL;--> statement-breakpoint
ALTER TABLE `chapter_links` ADD `deleted_at` text;--> statement-breakpoint
UPDATE `chapter_links` SET `updated_at` = `created_at` WHERE `updated_at` = '1970-01-01T00:00:00.000Z';--> statement-breakpoint
CREATE INDEX `chapter_links_user_idx` ON `chapter_links` (`user_id`);--> statement-breakpoint

-- ─────────────────────────── chapters (already had updated_at) ───────────────────────────
ALTER TABLE `chapters` ADD `user_id` text DEFAULT 'atlas-operator' NOT NULL;--> statement-breakpoint
ALTER TABLE `chapters` ADD `deleted_at` text;--> statement-breakpoint
CREATE INDEX `chapters_user_idx` ON `chapters` (`user_id`);--> statement-breakpoint

-- ─────────────────────────── decisions ───────────────────────────
ALTER TABLE `decisions` ADD `user_id` text DEFAULT 'atlas-operator' NOT NULL;--> statement-breakpoint
ALTER TABLE `decisions` ADD `updated_at` text DEFAULT '1970-01-01T00:00:00.000Z' NOT NULL;--> statement-breakpoint
ALTER TABLE `decisions` ADD `deleted_at` text;--> statement-breakpoint
UPDATE `decisions` SET `updated_at` = `created_at` WHERE `updated_at` = '1970-01-01T00:00:00.000Z';--> statement-breakpoint
CREATE INDEX `decisions_user_idx` ON `decisions` (`user_id`);--> statement-breakpoint

-- ─────────────────────────── entries ───────────────────────────
ALTER TABLE `entries` ADD `user_id` text DEFAULT 'atlas-operator' NOT NULL;--> statement-breakpoint
ALTER TABLE `entries` ADD `updated_at` text DEFAULT '1970-01-01T00:00:00.000Z' NOT NULL;--> statement-breakpoint
ALTER TABLE `entries` ADD `deleted_at` text;--> statement-breakpoint
UPDATE `entries` SET `updated_at` = `created_at` WHERE `updated_at` = '1970-01-01T00:00:00.000Z';--> statement-breakpoint
CREATE INDEX `entries_user_idx` ON `entries` (`user_id`);--> statement-breakpoint

-- ─────────────────────────── events ───────────────────────────
ALTER TABLE `events` ADD `user_id` text DEFAULT 'atlas-operator' NOT NULL;--> statement-breakpoint
ALTER TABLE `events` ADD `updated_at` text DEFAULT '1970-01-01T00:00:00.000Z' NOT NULL;--> statement-breakpoint
ALTER TABLE `events` ADD `deleted_at` text;--> statement-breakpoint
UPDATE `events` SET `updated_at` = `created_at` WHERE `updated_at` = '1970-01-01T00:00:00.000Z';--> statement-breakpoint
CREATE INDEX `events_user_idx` ON `events` (`user_id`);--> statement-breakpoint

-- ─────────────────────────── proposals ───────────────────────────
ALTER TABLE `proposals` ADD `user_id` text DEFAULT 'atlas-operator' NOT NULL;--> statement-breakpoint
ALTER TABLE `proposals` ADD `updated_at` text DEFAULT '1970-01-01T00:00:00.000Z' NOT NULL;--> statement-breakpoint
ALTER TABLE `proposals` ADD `deleted_at` text;--> statement-breakpoint
UPDATE `proposals` SET `updated_at` = COALESCE(`decided_at`, `created_at`) WHERE `updated_at` = '1970-01-01T00:00:00.000Z';--> statement-breakpoint
CREATE INDEX `proposals_user_idx` ON `proposals` (`user_id`);--> statement-breakpoint

-- ─────────────────────────── signals (create-time col is arrived_at) ───────────────────────────
ALTER TABLE `signals` ADD `user_id` text DEFAULT 'atlas-operator' NOT NULL;--> statement-breakpoint
ALTER TABLE `signals` ADD `updated_at` text DEFAULT '1970-01-01T00:00:00.000Z' NOT NULL;--> statement-breakpoint
ALTER TABLE `signals` ADD `deleted_at` text;--> statement-breakpoint
UPDATE `signals` SET `updated_at` = `arrived_at` WHERE `updated_at` = '1970-01-01T00:00:00.000Z';--> statement-breakpoint
CREATE INDEX `signals_user_idx` ON `signals` (`user_id`);--> statement-breakpoint

-- ─────────────────────────── todos ───────────────────────────
ALTER TABLE `todos` ADD `user_id` text DEFAULT 'atlas-operator' NOT NULL;--> statement-breakpoint
ALTER TABLE `todos` ADD `updated_at` text DEFAULT '1970-01-01T00:00:00.000Z' NOT NULL;--> statement-breakpoint
ALTER TABLE `todos` ADD `deleted_at` text;--> statement-breakpoint
UPDATE `todos` SET `updated_at` = COALESCE(`done_at`, `created_at`) WHERE `updated_at` = '1970-01-01T00:00:00.000Z';--> statement-breakpoint
CREATE INDEX `todos_user_idx` ON `todos` (`user_id`);--> statement-breakpoint

-- ─────────────────────────── watchers ───────────────────────────
ALTER TABLE `watchers` ADD `user_id` text DEFAULT 'atlas-operator' NOT NULL;--> statement-breakpoint
ALTER TABLE `watchers` ADD `updated_at` text DEFAULT '1970-01-01T00:00:00.000Z' NOT NULL;--> statement-breakpoint
ALTER TABLE `watchers` ADD `deleted_at` text;--> statement-breakpoint
UPDATE `watchers` SET `updated_at` = COALESCE(`last_checked`, `created_at`) WHERE `updated_at` = '1970-01-01T00:00:00.000Z';--> statement-breakpoint
CREATE INDEX `watchers_user_idx` ON `watchers` (`user_id`);
