import { initTRPC, TRPCError } from "@trpc/server";
import superjson from "superjson";
import { ZodError } from "zod";
import { extractBearer, resolveUserIdFromToken } from "./auth";

/**
 * tRPC context (SERVER_ARCHITECTURE.md §4.f, §4.d).
 *
 * `createContext` resolves the `Authorization: Bearer <deviceToken>` header to a
 * `userId` via the hashed `device_tokens` table. There is NO `DEFAULT_USER_ID`
 * fail-open: an absent / unknown / revoked token leaves `userId` null, and
 * `protectedProcedure` turns that into a 401.
 *
 * `createContext` itself never throws on a bad token — it only resolves what it
 * can. Authorization is enforced per-procedure by the middleware below, so a
 * future public procedure (e.g. health) can opt out without special-casing the
 * context.
 */
export interface Context {
  userId: string | null;
}

/**
 * Build the request context from incoming headers. Wired into the fetch adapter
 * in src/app/api/trpc/[trpc]/route.ts.
 */
export function createContext(opts: { headers: Headers }): Context {
  const token = extractBearer(opts.headers.get("authorization"));
  const userId = resolveUserIdFromToken(token);
  return { userId };
}

const t = initTRPC.context<Context>().create({
  transformer: superjson,
  errorFormatter({ shape, error }) {
    return {
      ...shape,
      data: {
        ...shape.data,
        zodError:
          error.cause instanceof ZodError ? error.cause.flatten() : null,
      },
    };
  },
});

/**
 * Auth middleware: require a resolved `userId`. Absent/unknown/revoked tokens
 * (userId === null) are rejected with UNAUTHORIZED before any handler runs.
 * Narrows `ctx.userId` to a non-null string for downstream procedures.
 */
const enforceAuth = t.middleware(({ ctx, next }) => {
  if (!ctx.userId) {
    throw new TRPCError({
      code: "UNAUTHORIZED",
      message: "Missing or invalid device token.",
    });
  }
  return next({ ctx: { ...ctx, userId: ctx.userId } });
});

export const router = t.router;
export const createCallerFactory = t.createCallerFactory;

/**
 * Open procedure — no auth. Reserve for genuinely public surfaces (e.g. health).
 * User-owned data routers must use `protectedProcedure`.
 */
export const publicProcedure = t.procedure;

/**
 * Authenticated procedure. `ctx.userId` is a guaranteed non-null string here;
 * thread it into every query/mutation as a WHERE predicate and every insert
 * (per-user isolation, §4.f).
 */
export const protectedProcedure = t.procedure.use(enforceAuth);
