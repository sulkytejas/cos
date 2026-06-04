ALTER TABLE `briefs` ADD `generated_by_event_id` text;--> statement-breakpoint
ALTER TABLE `events` ADD `claimed_at` text;--> statement-breakpoint
ALTER TABLE `events` ADD `attempts` integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE `events` ADD `dedupe_key` text;--> statement-breakpoint
CREATE UNIQUE INDEX `events_dedupe_key_unq` ON `events` (`dedupe_key`) WHERE "events"."dedupe_key" IS NOT NULL;--> statement-breakpoint
CREATE INDEX `events_status_created_idx` ON `events` (`status`,`created_at`);--> statement-breakpoint
ALTER TABLE `proposals` ADD `generated_by_event_id` text;