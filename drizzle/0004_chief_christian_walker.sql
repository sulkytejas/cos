CREATE TABLE `connector_state` (
	`source` text PRIMARY KEY NOT NULL,
	`cursor` text DEFAULT '0' NOT NULL,
	`updated_at` text DEFAULT (current_timestamp) NOT NULL
);
