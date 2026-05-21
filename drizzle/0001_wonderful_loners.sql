CREATE TABLE `briefs` (
	`id` text PRIMARY KEY NOT NULL,
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
	`created_at` text DEFAULT (current_timestamp) NOT NULL,
	FOREIGN KEY (`chapter_id`) REFERENCES `chapters`(`id`) ON UPDATE no action ON DELETE set null
);
--> statement-breakpoint
CREATE TABLE `dev_unknown_components` (
	`id` text PRIMARY KEY NOT NULL,
	`brief_id` text,
	`component_name` text NOT NULL,
	`raw_props` text,
	`logged_at` text DEFAULT (current_timestamp) NOT NULL
);
--> statement-breakpoint
CREATE TABLE `events` (
	`id` text PRIMARY KEY NOT NULL,
	`type` text NOT NULL,
	`payload` text NOT NULL,
	`status` text DEFAULT 'pending' NOT NULL,
	`created_at` text DEFAULT (current_timestamp) NOT NULL,
	`processed_at` text,
	`error` text
);
--> statement-breakpoint
CREATE TABLE `proposals` (
	`id` text PRIMARY KEY NOT NULL,
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
	`created_at` text DEFAULT (current_timestamp) NOT NULL,
	`decided_at` text,
	`decided_payload` text,
	FOREIGN KEY (`source_brief_id`) REFERENCES `briefs`(`id`) ON UPDATE no action ON DELETE set null,
	FOREIGN KEY (`chapter_id`) REFERENCES `chapters`(`id`) ON UPDATE no action ON DELETE set null
);
--> statement-breakpoint
CREATE TABLE `signals` (
	`id` text PRIMARY KEY NOT NULL,
	`source` text NOT NULL,
	`external_id` text,
	`raw_data` text NOT NULL,
	`summary` text,
	`processed` integer DEFAULT false NOT NULL,
	`arrived_at` text DEFAULT (current_timestamp) NOT NULL
);
--> statement-breakpoint
CREATE TABLE `watchers` (
	`id` text PRIMARY KEY NOT NULL,
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
	`created_at` text DEFAULT (current_timestamp) NOT NULL,
	FOREIGN KEY (`chapter_id`) REFERENCES `chapters`(`id`) ON UPDATE no action ON DELETE set null
);
--> statement-breakpoint
ALTER TABLE `chapter_links` ADD `proposed` integer DEFAULT false NOT NULL;--> statement-breakpoint
ALTER TABLE `decisions` ADD `source` text DEFAULT 'manual' NOT NULL;--> statement-breakpoint
ALTER TABLE `decisions` ADD `source_brief_id` text;--> statement-breakpoint
ALTER TABLE `decisions` ADD `source_signal_ids` text;--> statement-breakpoint
ALTER TABLE `entries` ADD `source_brief_id` text;--> statement-breakpoint
ALTER TABLE `entries` ADD `source_signal_ids` text;--> statement-breakpoint
ALTER TABLE `todos` ADD `source_brief_id` text;--> statement-breakpoint
ALTER TABLE `todos` ADD `source_signal_ids` text;