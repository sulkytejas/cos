-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║ 0008 — Phase 4 delta-sync prerequisites (SERVER_ARCHITECTURE.md §4.d)      ║
-- ╠══════════════════════════════════════════════════════════════════════════╣
-- ║ A. Timestamp normalization (runs FIRST, before the table rebuild copies     ║
-- ║    rows): every pre-existing space-format timestamp (`YYYY-MM-DD HH:MM:SS`, ║
-- ║    written by SQLite's `current_timestamp`) is rewritten to ISO-8601-UTC    ║
-- ║    (`YYYY-MM-DDTHH:MM:SS.sssZ`, the shape every app-level `toISOString()`    ║
-- ║    edit already writes). Lexically `' '(0x20) < 'T'(0x54)`, so a mixed-      ║
-- ║    format column makes the `(updatedAt,id)` sync cursor non-monotonic and   ║
-- ║    silently skips rows; this backfill makes lexical order == chronological. ║
-- ║ B. The drizzle-generated rebuild below switches every `(current_timestamp)` ║
-- ║    column default to the same ISO strftime form (matches `ISO_NOW` in       ║
-- ║    schema.ts) and adds the new sync columns `client_ref` (idempotent replay ║
-- ║    / optimistic-row reconciliation) + `source_proposal_id` (UNIQUE push-    ║
-- ║    idempotency on the approve fan-out). The rebuild's INSERT…SELECT copies   ║
-- ║    the already-normalized values, so the new tables are born all-ISO.       ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- ── A. Backfill existing space-format timestamps → ISO-8601-UTC ───────────────
-- Only rows whose value has a space at offset 11 (`____-__-__ __:__:__`) are
-- rewritten; already-ISO values (a 'T' at offset 11) and NULLs are left
-- untouched — idempotent and safe to re-run. `strftime('%Y-%m-%dT%H:%M:%fZ',col)`
-- parses the space-format string as UTC and re-emits it ISO with ms + 'Z'.
UPDATE `chapters`        SET `created_at` = strftime('%Y-%m-%dT%H:%M:%fZ', `created_at`) WHERE substr(`created_at`,11,1) = ' ';--> statement-breakpoint
UPDATE `chapters`        SET `updated_at` = strftime('%Y-%m-%dT%H:%M:%fZ', `updated_at`) WHERE substr(`updated_at`,11,1) = ' ';--> statement-breakpoint
UPDATE `todos`           SET `created_at` = strftime('%Y-%m-%dT%H:%M:%fZ', `created_at`) WHERE substr(`created_at`,11,1) = ' ';--> statement-breakpoint
UPDATE `todos`           SET `updated_at` = strftime('%Y-%m-%dT%H:%M:%fZ', `updated_at`) WHERE substr(`updated_at`,11,1) = ' ';--> statement-breakpoint
UPDATE `todos`           SET `done_at`    = strftime('%Y-%m-%dT%H:%M:%fZ', `done_at`)    WHERE `done_at`    IS NOT NULL AND substr(`done_at`,11,1)    = ' ';--> statement-breakpoint
UPDATE `decisions`       SET `created_at` = strftime('%Y-%m-%dT%H:%M:%fZ', `created_at`) WHERE substr(`created_at`,11,1) = ' ';--> statement-breakpoint
UPDATE `decisions`       SET `updated_at` = strftime('%Y-%m-%dT%H:%M:%fZ', `updated_at`) WHERE substr(`updated_at`,11,1) = ' ';--> statement-breakpoint
UPDATE `decisions`       SET `decided_at` = strftime('%Y-%m-%dT%H:%M:%fZ', `decided_at`) WHERE substr(`decided_at`,11,1) = ' ';--> statement-breakpoint
UPDATE `entries`         SET `created_at` = strftime('%Y-%m-%dT%H:%M:%fZ', `created_at`) WHERE substr(`created_at`,11,1) = ' ';--> statement-breakpoint
UPDATE `entries`         SET `updated_at` = strftime('%Y-%m-%dT%H:%M:%fZ', `updated_at`) WHERE substr(`updated_at`,11,1) = ' ';--> statement-breakpoint
UPDATE `chapter_links`   SET `created_at` = strftime('%Y-%m-%dT%H:%M:%fZ', `created_at`) WHERE substr(`created_at`,11,1) = ' ';--> statement-breakpoint
UPDATE `chapter_links`   SET `updated_at` = strftime('%Y-%m-%dT%H:%M:%fZ', `updated_at`) WHERE substr(`updated_at`,11,1) = ' ';--> statement-breakpoint
UPDATE `briefs`          SET `created_at` = strftime('%Y-%m-%dT%H:%M:%fZ', `created_at`) WHERE substr(`created_at`,11,1) = ' ';--> statement-breakpoint
UPDATE `briefs`          SET `updated_at` = strftime('%Y-%m-%dT%H:%M:%fZ', `updated_at`) WHERE substr(`updated_at`,11,1) = ' ';--> statement-breakpoint
UPDATE `briefs`          SET `surface_at` = strftime('%Y-%m-%dT%H:%M:%fZ', `surface_at`) WHERE substr(`surface_at`,11,1) = ' ';--> statement-breakpoint
UPDATE `briefs`          SET `expires_at` = strftime('%Y-%m-%dT%H:%M:%fZ', `expires_at`) WHERE `expires_at` IS NOT NULL AND substr(`expires_at`,11,1) = ' ';--> statement-breakpoint
UPDATE `events`          SET `created_at`   = strftime('%Y-%m-%dT%H:%M:%fZ', `created_at`)   WHERE substr(`created_at`,11,1) = ' ';--> statement-breakpoint
UPDATE `events`          SET `updated_at`   = strftime('%Y-%m-%dT%H:%M:%fZ', `updated_at`)   WHERE substr(`updated_at`,11,1) = ' ';--> statement-breakpoint
UPDATE `events`          SET `claimed_at`   = strftime('%Y-%m-%dT%H:%M:%fZ', `claimed_at`)   WHERE `claimed_at`   IS NOT NULL AND substr(`claimed_at`,11,1)   = ' ';--> statement-breakpoint
UPDATE `events`          SET `processed_at` = strftime('%Y-%m-%dT%H:%M:%fZ', `processed_at`) WHERE `processed_at` IS NOT NULL AND substr(`processed_at`,11,1) = ' ';--> statement-breakpoint
UPDATE `watchers`        SET `created_at`   = strftime('%Y-%m-%dT%H:%M:%fZ', `created_at`)   WHERE substr(`created_at`,11,1) = ' ';--> statement-breakpoint
UPDATE `watchers`        SET `updated_at`   = strftime('%Y-%m-%dT%H:%M:%fZ', `updated_at`)   WHERE substr(`updated_at`,11,1) = ' ';--> statement-breakpoint
UPDATE `watchers`        SET `next_check`   = strftime('%Y-%m-%dT%H:%M:%fZ', `next_check`)   WHERE substr(`next_check`,11,1) = ' ';--> statement-breakpoint
UPDATE `watchers`        SET `last_checked` = strftime('%Y-%m-%dT%H:%M:%fZ', `last_checked`) WHERE `last_checked` IS NOT NULL AND substr(`last_checked`,11,1) = ' ';--> statement-breakpoint
UPDATE `signals`         SET `arrived_at` = strftime('%Y-%m-%dT%H:%M:%fZ', `arrived_at`) WHERE substr(`arrived_at`,11,1) = ' ';--> statement-breakpoint
UPDATE `signals`         SET `updated_at` = strftime('%Y-%m-%dT%H:%M:%fZ', `updated_at`) WHERE substr(`updated_at`,11,1) = ' ';--> statement-breakpoint
UPDATE `proposals`       SET `created_at` = strftime('%Y-%m-%dT%H:%M:%fZ', `created_at`) WHERE substr(`created_at`,11,1) = ' ';--> statement-breakpoint
UPDATE `proposals`       SET `updated_at` = strftime('%Y-%m-%dT%H:%M:%fZ', `updated_at`) WHERE substr(`updated_at`,11,1) = ' ';--> statement-breakpoint
UPDATE `proposals`       SET `decided_at` = strftime('%Y-%m-%dT%H:%M:%fZ', `decided_at`) WHERE `decided_at` IS NOT NULL AND substr(`decided_at`,11,1) = ' ';--> statement-breakpoint
UPDATE `usage_ledger`    SET `created_at` = strftime('%Y-%m-%dT%H:%M:%fZ', `created_at`) WHERE substr(`created_at`,11,1) = ' ';--> statement-breakpoint
UPDATE `usage_ledger`    SET `updated_at` = strftime('%Y-%m-%dT%H:%M:%fZ', `updated_at`) WHERE substr(`updated_at`,11,1) = ' ';--> statement-breakpoint
UPDATE `device_tokens`   SET `created_at`   = strftime('%Y-%m-%dT%H:%M:%fZ', `created_at`)   WHERE substr(`created_at`,11,1) = ' ';--> statement-breakpoint
UPDATE `device_tokens`   SET `last_seen_at` = strftime('%Y-%m-%dT%H:%M:%fZ', `last_seen_at`) WHERE `last_seen_at` IS NOT NULL AND substr(`last_seen_at`,11,1) = ' ';--> statement-breakpoint
UPDATE `connector_state` SET `updated_at` = strftime('%Y-%m-%dT%H:%M:%fZ', `updated_at`) WHERE substr(`updated_at`,11,1) = ' ';--> statement-breakpoint
UPDATE `dev_unknown_components` SET `logged_at` = strftime('%Y-%m-%dT%H:%M:%fZ', `logged_at`) WHERE substr(`logged_at`,11,1) = ' ';--> statement-breakpoint

-- ── B. Drizzle-generated rebuild: ISO defaults + new sync columns/indexes ─────
PRAGMA foreign_keys=OFF;--> statement-breakpoint
CREATE TABLE `__new_briefs` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text DEFAULT 'atlas-operator' NOT NULL,
	`chapter_id` text,
	`title` text NOT NULL,
	`situation_description` text NOT NULL,
	`structure` text NOT NULL,
	`primary_action` text,
	`secondary_actions` text,
	`status` text DEFAULT 'draft' NOT NULL,
	`surface_at` text NOT NULL,
	`expires_at` text,
	`chapter_title` text,
	`relevance` text,
	`when` text,
	`drafted` text,
	`preview` text,
	`agent_trace` text,
	`generated_by_event_id` text,
	`created_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) NOT NULL,
	`updated_at` text NOT NULL,
	`deleted_at` text,
	FOREIGN KEY (`chapter_id`) REFERENCES `chapters`(`id`) ON UPDATE no action ON DELETE set null
);
--> statement-breakpoint
INSERT INTO `__new_briefs`("id", "user_id", "chapter_id", "title", "situation_description", "structure", "primary_action", "secondary_actions", "status", "surface_at", "expires_at", "chapter_title", "relevance", "when", "drafted", "preview", "agent_trace", "generated_by_event_id", "created_at", "updated_at", "deleted_at") SELECT "id", "user_id", "chapter_id", "title", "situation_description", "structure", "primary_action", "secondary_actions", "status", "surface_at", "expires_at", "chapter_title", "relevance", "when", "drafted", "preview", "agent_trace", "generated_by_event_id", "created_at", "updated_at", "deleted_at" FROM `briefs`;--> statement-breakpoint
DROP TABLE `briefs`;--> statement-breakpoint
ALTER TABLE `__new_briefs` RENAME TO `briefs`;--> statement-breakpoint
PRAGMA foreign_keys=ON;--> statement-breakpoint
CREATE INDEX `briefs_user_idx` ON `briefs` (`user_id`);--> statement-breakpoint
CREATE TABLE `__new_chapter_links` (
	`user_id` text DEFAULT 'atlas-operator' NOT NULL,
	`from_id` text NOT NULL,
	`to_id` text NOT NULL,
	`relation` text DEFAULT 'related' NOT NULL,
	`note` text,
	`proposed` integer DEFAULT false NOT NULL,
	`created_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) NOT NULL,
	`updated_at` text NOT NULL,
	`deleted_at` text,
	PRIMARY KEY(`from_id`, `to_id`, `relation`),
	FOREIGN KEY (`from_id`) REFERENCES `chapters`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`to_id`) REFERENCES `chapters`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
INSERT INTO `__new_chapter_links`("user_id", "from_id", "to_id", "relation", "note", "proposed", "created_at", "updated_at", "deleted_at") SELECT "user_id", "from_id", "to_id", "relation", "note", "proposed", "created_at", "updated_at", "deleted_at" FROM `chapter_links`;--> statement-breakpoint
DROP TABLE `chapter_links`;--> statement-breakpoint
ALTER TABLE `__new_chapter_links` RENAME TO `chapter_links`;--> statement-breakpoint
CREATE INDEX `chapter_links_user_idx` ON `chapter_links` (`user_id`);--> statement-breakpoint
CREATE TABLE `__new_chapters` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text DEFAULT 'atlas-operator' NOT NULL,
	`title` text NOT NULL,
	`type` text NOT NULL,
	`status` text DEFAULT 'active' NOT NULL,
	`start_date` text,
	`end_date` text,
	`purpose` text,
	`client_ref` text,
	`created_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) NOT NULL,
	`updated_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) NOT NULL,
	`deleted_at` text
);
--> statement-breakpoint
-- NOTE: `client_ref` is a NEW column — it does not exist on the OLD `chapters`
-- table being copied FROM, so it is omitted here and defaults to NULL on the
-- rebuilt table. (Drizzle-kit erroneously included it in the SELECT.)
INSERT INTO `__new_chapters`("id", "user_id", "title", "type", "status", "start_date", "end_date", "purpose", "created_at", "updated_at", "deleted_at") SELECT "id", "user_id", "title", "type", "status", "start_date", "end_date", "purpose", "created_at", "updated_at", "deleted_at" FROM `chapters`;--> statement-breakpoint
DROP TABLE `chapters`;--> statement-breakpoint
ALTER TABLE `__new_chapters` RENAME TO `chapters`;--> statement-breakpoint
CREATE INDEX `chapters_user_idx` ON `chapters` (`user_id`);--> statement-breakpoint
CREATE UNIQUE INDEX `chapters_user_client_ref_unq` ON `chapters` (`user_id`,`client_ref`) WHERE "chapters"."client_ref" IS NOT NULL;--> statement-breakpoint
CREATE TABLE `__new_connector_state` (
	`source` text PRIMARY KEY NOT NULL,
	`cursor` text DEFAULT '0' NOT NULL,
	`updated_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) NOT NULL
);
--> statement-breakpoint
INSERT INTO `__new_connector_state`("source", "cursor", "updated_at") SELECT "source", "cursor", "updated_at" FROM `connector_state`;--> statement-breakpoint
DROP TABLE `connector_state`;--> statement-breakpoint
ALTER TABLE `__new_connector_state` RENAME TO `connector_state`;--> statement-breakpoint
CREATE TABLE `__new_decisions` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text DEFAULT 'atlas-operator' NOT NULL,
	`chapter_id` text NOT NULL,
	`title` text NOT NULL,
	`rationale` text,
	`options_considered` text,
	`decided_at` text NOT NULL,
	`source` text DEFAULT 'manual' NOT NULL,
	`source_brief_id` text,
	`source_signal_ids` text,
	`source_proposal_id` text,
	`client_ref` text,
	`created_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) NOT NULL,
	`updated_at` text NOT NULL,
	`deleted_at` text,
	FOREIGN KEY (`chapter_id`) REFERENCES `chapters`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
-- NOTE: `source_proposal_id` and `client_ref` are NEW columns absent on the OLD
-- `decisions` table — omitted from the copy, default NULL on the rebuilt table.
INSERT INTO `__new_decisions`("id", "user_id", "chapter_id", "title", "rationale", "options_considered", "decided_at", "source", "source_brief_id", "source_signal_ids", "created_at", "updated_at", "deleted_at") SELECT "id", "user_id", "chapter_id", "title", "rationale", "options_considered", "decided_at", "source", "source_brief_id", "source_signal_ids", "created_at", "updated_at", "deleted_at" FROM `decisions`;--> statement-breakpoint
DROP TABLE `decisions`;--> statement-breakpoint
ALTER TABLE `__new_decisions` RENAME TO `decisions`;--> statement-breakpoint
CREATE INDEX `decisions_user_idx` ON `decisions` (`user_id`);--> statement-breakpoint
CREATE UNIQUE INDEX `decisions_source_proposal_unq` ON `decisions` (`source_proposal_id`) WHERE "decisions"."source_proposal_id" IS NOT NULL;--> statement-breakpoint
CREATE UNIQUE INDEX `decisions_user_client_ref_unq` ON `decisions` (`user_id`,`client_ref`) WHERE "decisions"."client_ref" IS NOT NULL;--> statement-breakpoint
CREATE TABLE `__new_dev_unknown_components` (
	`id` text PRIMARY KEY NOT NULL,
	`brief_id` text,
	`component_name` text NOT NULL,
	`raw_props` text,
	`logged_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) NOT NULL
);
--> statement-breakpoint
INSERT INTO `__new_dev_unknown_components`("id", "brief_id", "component_name", "raw_props", "logged_at") SELECT "id", "brief_id", "component_name", "raw_props", "logged_at" FROM `dev_unknown_components`;--> statement-breakpoint
DROP TABLE `dev_unknown_components`;--> statement-breakpoint
ALTER TABLE `__new_dev_unknown_components` RENAME TO `dev_unknown_components`;--> statement-breakpoint
CREATE TABLE `__new_device_tokens` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`token_hash` text NOT NULL,
	`label` text DEFAULT 'device' NOT NULL,
	`created_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) NOT NULL,
	`last_seen_at` text,
	`revoked_at` text
);
--> statement-breakpoint
INSERT INTO `__new_device_tokens`("id", "user_id", "token_hash", "label", "created_at", "last_seen_at", "revoked_at") SELECT "id", "user_id", "token_hash", "label", "created_at", "last_seen_at", "revoked_at" FROM `device_tokens`;--> statement-breakpoint
DROP TABLE `device_tokens`;--> statement-breakpoint
ALTER TABLE `__new_device_tokens` RENAME TO `device_tokens`;--> statement-breakpoint
CREATE UNIQUE INDEX `device_tokens_token_hash_idx` ON `device_tokens` (`token_hash`);--> statement-breakpoint
CREATE INDEX `device_tokens_user_idx` ON `device_tokens` (`user_id`);--> statement-breakpoint
CREATE TABLE `__new_entries` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text DEFAULT 'atlas-operator' NOT NULL,
	`chapter_id` text NOT NULL,
	`date` text NOT NULL,
	`content` text NOT NULL,
	`source` text DEFAULT 'manual' NOT NULL,
	`source_brief_id` text,
	`source_signal_ids` text,
	`source_proposal_id` text,
	`client_ref` text,
	`created_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) NOT NULL,
	`updated_at` text NOT NULL,
	`deleted_at` text,
	FOREIGN KEY (`chapter_id`) REFERENCES `chapters`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
-- NOTE: `source_proposal_id` and `client_ref` are NEW columns absent on the OLD
-- `entries` table — omitted from the copy, default NULL on the rebuilt table.
INSERT INTO `__new_entries`("id", "user_id", "chapter_id", "date", "content", "source", "source_brief_id", "source_signal_ids", "created_at", "updated_at", "deleted_at") SELECT "id", "user_id", "chapter_id", "date", "content", "source", "source_brief_id", "source_signal_ids", "created_at", "updated_at", "deleted_at" FROM `entries`;--> statement-breakpoint
DROP TABLE `entries`;--> statement-breakpoint
ALTER TABLE `__new_entries` RENAME TO `entries`;--> statement-breakpoint
CREATE INDEX `entries_user_idx` ON `entries` (`user_id`);--> statement-breakpoint
CREATE UNIQUE INDEX `entries_source_proposal_unq` ON `entries` (`source_proposal_id`) WHERE "entries"."source_proposal_id" IS NOT NULL;--> statement-breakpoint
CREATE UNIQUE INDEX `entries_user_client_ref_unq` ON `entries` (`user_id`,`client_ref`) WHERE "entries"."client_ref" IS NOT NULL;--> statement-breakpoint
CREATE TABLE `__new_events` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text DEFAULT 'atlas-operator' NOT NULL,
	`type` text NOT NULL,
	`payload` text NOT NULL,
	`status` text DEFAULT 'pending' NOT NULL,
	`claimed_at` text,
	`attempts` integer DEFAULT 0 NOT NULL,
	`dedupe_key` text,
	`created_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) NOT NULL,
	`updated_at` text NOT NULL,
	`deleted_at` text,
	`processed_at` text,
	`error` text,
	`result` text
);
--> statement-breakpoint
INSERT INTO `__new_events`("id", "user_id", "type", "payload", "status", "claimed_at", "attempts", "dedupe_key", "created_at", "updated_at", "deleted_at", "processed_at", "error", "result") SELECT "id", "user_id", "type", "payload", "status", "claimed_at", "attempts", "dedupe_key", "created_at", "updated_at", "deleted_at", "processed_at", "error", "result" FROM `events`;--> statement-breakpoint
DROP TABLE `events`;--> statement-breakpoint
ALTER TABLE `__new_events` RENAME TO `events`;--> statement-breakpoint
CREATE UNIQUE INDEX `events_dedupe_key_unq` ON `events` (`dedupe_key`) WHERE "events"."dedupe_key" IS NOT NULL;--> statement-breakpoint
CREATE INDEX `events_status_created_idx` ON `events` (`status`,`created_at`);--> statement-breakpoint
CREATE INDEX `events_user_idx` ON `events` (`user_id`);--> statement-breakpoint
CREATE TABLE `__new_proposals` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text DEFAULT 'atlas-operator' NOT NULL,
	`type` text NOT NULL,
	`proposed_payload` text NOT NULL,
	`source_brief_id` text,
	`source_signal_ids` text,
	`chapter_id` text,
	`status` text DEFAULT 'pending' NOT NULL,
	`confidence` real DEFAULT 0.5 NOT NULL,
	`reasoning` text,
	`summary` text,
	`source_label` text,
	`source_meta` text,
	`question` text,
	`setup` text,
	`options` text,
	`created_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) NOT NULL,
	`updated_at` text NOT NULL,
	`deleted_at` text,
	`decided_at` text,
	`decided_payload` text,
	`generated_by_event_id` text,
	FOREIGN KEY (`source_brief_id`) REFERENCES `briefs`(`id`) ON UPDATE no action ON DELETE set null,
	FOREIGN KEY (`chapter_id`) REFERENCES `chapters`(`id`) ON UPDATE no action ON DELETE set null
);
--> statement-breakpoint
INSERT INTO `__new_proposals`("id", "user_id", "type", "proposed_payload", "source_brief_id", "source_signal_ids", "chapter_id", "status", "confidence", "reasoning", "summary", "source_label", "source_meta", "question", "setup", "options", "created_at", "updated_at", "deleted_at", "decided_at", "decided_payload", "generated_by_event_id") SELECT "id", "user_id", "type", "proposed_payload", "source_brief_id", "source_signal_ids", "chapter_id", "status", "confidence", "reasoning", "summary", "source_label", "source_meta", "question", "setup", "options", "created_at", "updated_at", "deleted_at", "decided_at", "decided_payload", "generated_by_event_id" FROM `proposals`;--> statement-breakpoint
DROP TABLE `proposals`;--> statement-breakpoint
ALTER TABLE `__new_proposals` RENAME TO `proposals`;--> statement-breakpoint
CREATE INDEX `proposals_user_idx` ON `proposals` (`user_id`);--> statement-breakpoint
CREATE TABLE `__new_signals` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text DEFAULT 'atlas-operator' NOT NULL,
	`source` text NOT NULL,
	`external_id` text,
	`raw_data` text NOT NULL,
	`summary` text,
	`processed` integer DEFAULT false NOT NULL,
	`arrived_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) NOT NULL,
	`updated_at` text NOT NULL,
	`deleted_at` text
);
--> statement-breakpoint
INSERT INTO `__new_signals`("id", "user_id", "source", "external_id", "raw_data", "summary", "processed", "arrived_at", "updated_at", "deleted_at") SELECT "id", "user_id", "source", "external_id", "raw_data", "summary", "processed", "arrived_at", "updated_at", "deleted_at" FROM `signals`;--> statement-breakpoint
DROP TABLE `signals`;--> statement-breakpoint
ALTER TABLE `__new_signals` RENAME TO `signals`;--> statement-breakpoint
CREATE INDEX `signals_user_idx` ON `signals` (`user_id`);--> statement-breakpoint
CREATE UNIQUE INDEX `signals_user_source_external_unq` ON `signals` (`user_id`,`source`,`external_id`) WHERE "signals"."external_id" IS NOT NULL;--> statement-breakpoint
CREATE TABLE `__new_todos` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text DEFAULT 'atlas-operator' NOT NULL,
	`chapter_id` text NOT NULL,
	`text` text NOT NULL,
	`done` integer DEFAULT false NOT NULL,
	`due_date` text,
	`source` text DEFAULT 'manual' NOT NULL,
	`source_brief_id` text,
	`source_signal_ids` text,
	`source_proposal_id` text,
	`client_ref` text,
	`created_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) NOT NULL,
	`updated_at` text NOT NULL,
	`deleted_at` text,
	`done_at` text,
	FOREIGN KEY (`chapter_id`) REFERENCES `chapters`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
-- NOTE: `source_proposal_id` and `client_ref` are NEW columns absent on the OLD
-- `todos` table — omitted from the copy, default NULL on the rebuilt table.
INSERT INTO `__new_todos`("id", "user_id", "chapter_id", "text", "done", "due_date", "source", "source_brief_id", "source_signal_ids", "created_at", "updated_at", "deleted_at", "done_at") SELECT "id", "user_id", "chapter_id", "text", "done", "due_date", "source", "source_brief_id", "source_signal_ids", "created_at", "updated_at", "deleted_at", "done_at" FROM `todos`;--> statement-breakpoint
DROP TABLE `todos`;--> statement-breakpoint
ALTER TABLE `__new_todos` RENAME TO `todos`;--> statement-breakpoint
CREATE INDEX `todos_user_idx` ON `todos` (`user_id`);--> statement-breakpoint
CREATE UNIQUE INDEX `todos_source_proposal_unq` ON `todos` (`source_proposal_id`) WHERE "todos"."source_proposal_id" IS NOT NULL;--> statement-breakpoint
CREATE UNIQUE INDEX `todos_user_client_ref_unq` ON `todos` (`user_id`,`client_ref`) WHERE "todos"."client_ref" IS NOT NULL;--> statement-breakpoint
CREATE TABLE `__new_usage_ledger` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`day` text NOT NULL,
	`chargeable_tokens` integer DEFAULT 0 NOT NULL,
	`input_tokens` integer DEFAULT 0 NOT NULL,
	`cache_creation_tokens` integer DEFAULT 0 NOT NULL,
	`cache_read_tokens` integer DEFAULT 0 NOT NULL,
	`output_tokens` integer DEFAULT 0 NOT NULL,
	`requests` integer DEFAULT 0 NOT NULL,
	`created_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) NOT NULL,
	`updated_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) NOT NULL
);
--> statement-breakpoint
INSERT INTO `__new_usage_ledger`("id", "user_id", "day", "chargeable_tokens", "input_tokens", "cache_creation_tokens", "cache_read_tokens", "output_tokens", "requests", "created_at", "updated_at") SELECT "id", "user_id", "day", "chargeable_tokens", "input_tokens", "cache_creation_tokens", "cache_read_tokens", "output_tokens", "requests", "created_at", "updated_at" FROM `usage_ledger`;--> statement-breakpoint
DROP TABLE `usage_ledger`;--> statement-breakpoint
ALTER TABLE `__new_usage_ledger` RENAME TO `usage_ledger`;--> statement-breakpoint
CREATE UNIQUE INDEX `usage_ledger_user_day_idx` ON `usage_ledger` (`user_id`,`day`);--> statement-breakpoint
CREATE TABLE `__new_watchers` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text DEFAULT 'atlas-operator' NOT NULL,
	`chapter_id` text,
	`description` text NOT NULL,
	`prompt` text NOT NULL,
	`source_type` text DEFAULT 'internal' NOT NULL,
	`last_checked` text,
	`next_check` text NOT NULL,
	`cadence_minutes` integer DEFAULT 180 NOT NULL,
	`status` text DEFAULT 'active' NOT NULL,
	`last_finding` text,
	`cadence_label` text,
	`created_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) NOT NULL,
	`updated_at` text NOT NULL,
	`deleted_at` text,
	FOREIGN KEY (`chapter_id`) REFERENCES `chapters`(`id`) ON UPDATE no action ON DELETE set null
);
--> statement-breakpoint
INSERT INTO `__new_watchers`("id", "user_id", "chapter_id", "description", "prompt", "source_type", "last_checked", "next_check", "cadence_minutes", "status", "last_finding", "cadence_label", "created_at", "updated_at", "deleted_at") SELECT "id", "user_id", "chapter_id", "description", "prompt", "source_type", "last_checked", "next_check", "cadence_minutes", "status", "last_finding", "cadence_label", "created_at", "updated_at", "deleted_at" FROM `watchers`;--> statement-breakpoint
DROP TABLE `watchers`;--> statement-breakpoint
ALTER TABLE `__new_watchers` RENAME TO `watchers`;--> statement-breakpoint
CREATE INDEX `watchers_user_idx` ON `watchers` (`user_id`);