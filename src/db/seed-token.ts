/**
 * Operator device-token seeder (SERVER_ARCHITECTURE.md §4.f).
 *
 * Single-tenant bootstrap: open `register` is disabled for the MVP, so the one
 * operator token is minted HERE at deploy time and printed exactly once. We
 * store ONLY its sha256(token + AUTH_TOKEN_PEPPER) hash — the plaintext below is
 * unrecoverable afterward, so copy it into the iOS Keychain immediately.
 *
 *   AUTH_TOKEN_PEPPER=... tsx src/db/seed-token.ts            # mint operator token
 *   AUTH_TOKEN_PEPPER=... tsx src/db/seed-token.ts --label my-iphone
 *   AUTH_TOKEN_PEPPER=... tsx src/db/seed-token.ts --force    # mint even if one exists
 *
 * Deploy intentionally does NOT call this automatically (it prints a live
 * credential to logs); the operator runs it once by hand. By default it refuses
 * to mint a second active token for the same user — pass --force to add another
 * device — so a re-run of the deploy never silently issues extra credentials.
 */
import { randomUUID } from "node:crypto";
import { and, eq, isNull } from "drizzle-orm";
import { db } from "./client";
import { deviceTokens } from "./schema";
import { generateToken, hashToken } from "@/server/auth";

/** Default operator user — matches ATLAS_USER_ID used by the worker and /api/ask. */
const OPERATOR_USER_ID = process.env.ATLAS_USER_ID ?? "atlas-operator";

interface SeedOptions {
  userId?: string;
  label?: string;
  force?: boolean;
}

/**
 * Mint one device token for `userId`, store its hash, and return the plaintext
 * exactly once (the caller is responsible for displaying it). Returns null when
 * an active token already exists and `force` is not set.
 */
export function seedDeviceToken(opts: SeedOptions = {}): {
  token: string;
  id: string;
  userId: string;
  label: string;
} | null {
  const userId = opts.userId ?? OPERATOR_USER_ID;
  const label = opts.label ?? "operator";

  if (!opts.force) {
    const existing = db
      .select({ id: deviceTokens.id })
      .from(deviceTokens)
      .where(and(eq(deviceTokens.userId, userId), isNull(deviceTokens.revokedAt)))
      .get();
    if (existing) return null;
  }

  const token = generateToken();
  const id = randomUUID();

  db.insert(deviceTokens)
    .values({
      id,
      userId,
      // hashToken throws if AUTH_TOKEN_PEPPER is unset — minting without a pepper
      // is a launch blocker, so failing loudly here is correct.
      tokenHash: hashToken(token),
      label,
    })
    .run();

  return { token, id, userId, label };
}

if (require.main === module) {
  const args = process.argv.slice(2);
  const force = args.includes("--force");
  const labelIdx = args.indexOf("--label");
  const label = labelIdx >= 0 ? args[labelIdx + 1] : undefined;
  const userIdx = args.indexOf("--user");
  const userId = userIdx >= 0 ? args[userIdx + 1] : undefined;

  try {
    const result = seedDeviceToken({ force, label, userId });
    if (!result) {
      console.error(
        "[atlas] an active device token already exists for this user.\n" +
          "        Re-run with --force to mint an additional device token.",
      );
      process.exit(1);
    }
    // Print the plaintext ONCE — it is never recoverable from the DB.
    console.log("");
    console.log("  ┌─────────────────────────────────────────────────────────────");
    console.log("  │ Atlas operator device token (shown once — copy it now)");
    console.log("  │");
    console.log(`  │   userId : ${result.userId}`);
    console.log(`  │   label  : ${result.label}`);
    console.log(`  │   id     : ${result.id}`);
    console.log("  │");
    console.log(`  │   TOKEN  : ${result.token}`);
    console.log("  │");
    console.log("  │ Send it as:  Authorization: Bearer <TOKEN>");
    console.log("  │ Store it in the iOS Keychain. Only its hash is in the DB.");
    console.log("  └─────────────────────────────────────────────────────────────");
    console.log("");
    process.exit(0);
  } catch (err) {
    console.error("[atlas] failed to mint device token:", (err as Error).message);
    process.exit(1);
  }
}
