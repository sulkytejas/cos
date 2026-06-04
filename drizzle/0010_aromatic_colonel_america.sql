CREATE TABLE `trip_preferences` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text DEFAULT 'atlas-operator' NOT NULL,
	`trip_id` text NOT NULL,
	`pref_key` text NOT NULL,
	`pref_value` text NOT NULL,
	`learned` text NOT NULL,
	`evidence` text,
	`weight` integer DEFAULT 1 NOT NULL,
	`created_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) NOT NULL,
	`updated_at` text NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `trip_preferences_user_trip_key_unq` ON `trip_preferences` (`user_id`,`trip_id`,`pref_key`);--> statement-breakpoint
CREATE INDEX `trip_preferences_user_idx` ON `trip_preferences` (`user_id`);--> statement-breakpoint
CREATE TABLE `trip_state` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text DEFAULT 'atlas-operator' NOT NULL,
	`trip_id` text NOT NULL,
	`leg_patches` text DEFAULT '{}' NOT NULL,
	`connector_grants` text DEFAULT '{}' NOT NULL,
	`needs_rederive` integer DEFAULT false NOT NULL,
	`created_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) NOT NULL,
	`updated_at` text NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `trip_state_user_trip_unq` ON `trip_state` (`user_id`,`trip_id`);--> statement-breakpoint
CREATE INDEX `trip_state_user_idx` ON `trip_state` (`user_id`);