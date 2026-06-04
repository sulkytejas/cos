CREATE TABLE `connector_accounts` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text DEFAULT 'atlas-operator' NOT NULL,
	`source` text NOT NULL,
	`account_email` text,
	`refresh_token_ciphertext` text NOT NULL,
	`refresh_token_iv` text NOT NULL,
	`refresh_token_tag` text NOT NULL,
	`scope` text,
	`sync_cursor` text,
	`status` text DEFAULT 'active' NOT NULL,
	`last_polled_at` text,
	`last_error` text,
	`created_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) NOT NULL,
	`updated_at` text NOT NULL,
	`deleted_at` text
);
--> statement-breakpoint
CREATE UNIQUE INDEX `connector_accounts_user_source_unq` ON `connector_accounts` (`user_id`,`source`);--> statement-breakpoint
CREATE INDEX `connector_accounts_user_idx` ON `connector_accounts` (`user_id`);--> statement-breakpoint
PRAGMA foreign_keys=OFF;--> statement-breakpoint
CREATE TABLE `__new_connector_state` (
	`user_id` text DEFAULT 'atlas-operator' NOT NULL,
	`source` text NOT NULL,
	`cursor` text DEFAULT '0' NOT NULL,
	`updated_at` text DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')) NOT NULL,
	PRIMARY KEY(`user_id`, `source`)
);
--> statement-breakpoint
INSERT INTO `__new_connector_state`("user_id", "source", "cursor", "updated_at") SELECT 'atlas-operator', "source", "cursor", "updated_at" FROM `connector_state`;--> statement-breakpoint
DROP TABLE `connector_state`;--> statement-breakpoint
ALTER TABLE `__new_connector_state` RENAME TO `connector_state`;--> statement-breakpoint
PRAGMA foreign_keys=ON;