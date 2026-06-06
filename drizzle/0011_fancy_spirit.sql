CREATE TABLE `turns` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text DEFAULT 'atlas-operator' NOT NULL,
	`role` text NOT NULL,
	`kind` text DEFAULT 'message' NOT NULL,
	`body` text NOT NULL,
	`source_tag` text,
	`brief_ids` text,
	`memo` text,
	`connector` text,
	`meta` text,
	`generated_by_event_id` text,
	`created_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) NOT NULL,
	`updated_at` text NOT NULL,
	`deleted_at` text
);
--> statement-breakpoint
CREATE INDEX `turns_user_idx` ON `turns` (`user_id`);--> statement-breakpoint
ALTER TABLE `chapters` ADD `palette` text;