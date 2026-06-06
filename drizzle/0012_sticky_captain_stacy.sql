CREATE TABLE `digests` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text DEFAULT 'atlas-operator' NOT NULL,
	`body` text NOT NULL,
	`source_observation_ids` text DEFAULT '[]' NOT NULL,
	`built_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) NOT NULL,
	`created_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) NOT NULL,
	`updated_at` text NOT NULL,
	`deleted_at` text
);
--> statement-breakpoint
CREATE UNIQUE INDEX `digests_user_unq` ON `digests` (`user_id`);--> statement-breakpoint
CREATE TABLE `observation_about` (
	`user_id` text DEFAULT 'atlas-operator' NOT NULL,
	`observation_id` text NOT NULL,
	`handle` text NOT NULL,
	`created_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) NOT NULL,
	PRIMARY KEY(`observation_id`, `handle`),
	FOREIGN KEY (`observation_id`) REFERENCES `observations`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `observation_about_user_handle_idx` ON `observation_about` (`user_id`,`handle`);--> statement-breakpoint
CREATE TABLE `observations` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text DEFAULT 'atlas-operator' NOT NULL,
	`body` text NOT NULL,
	`kind` text DEFAULT 'fact' NOT NULL,
	`source` text DEFAULT 'observed' NOT NULL,
	`confidence` real DEFAULT 0.5 NOT NULL,
	`receipts` text NOT NULL,
	`first_seen_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) NOT NULL,
	`last_seen_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) NOT NULL,
	`weight` integer DEFAULT 1 NOT NULL,
	`invalidated_at` text,
	`superseded_by_id` text,
	`struck_at` text,
	`generated_by_event_id` text,
	`created_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) NOT NULL,
	`updated_at` text NOT NULL,
	`deleted_at` text,
	FOREIGN KEY (`superseded_by_id`) REFERENCES `observations`(`id`) ON UPDATE no action ON DELETE set null
);
--> statement-breakpoint
CREATE INDEX `observations_user_idx` ON `observations` (`user_id`);--> statement-breakpoint
CREATE TABLE `people` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text DEFAULT 'atlas-operator' NOT NULL,
	`canonical_name` text NOT NULL,
	`handles` text DEFAULT '[]' NOT NULL,
	`role` text,
	`org` text,
	`first_seen_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) NOT NULL,
	`last_seen_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) NOT NULL,
	`merged_into_id` text,
	`created_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) NOT NULL,
	`updated_at` text NOT NULL,
	`deleted_at` text,
	FOREIGN KEY (`merged_into_id`) REFERENCES `people`(`id`) ON UPDATE no action ON DELETE set null
);
--> statement-breakpoint
CREATE INDEX `people_user_idx` ON `people` (`user_id`);