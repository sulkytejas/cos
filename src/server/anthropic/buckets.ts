/**
 * The throttle — a triple continuous-refill token bucket (RPM / ITPM / OTPM)
 * per route, a global concurrency cap, branched 429/529/401 handling, a circuit
 * breaker, and header-driven self-clamping.
 *
 * SERVER_ARCHITECTURE.md §4.b. The model here mirrors Anthropic's own: each
 * bucket refills continuously toward its configured capacity, and a request must
 * acquire from ALL THREE before sending (reserve-then-reconcile):
 *   - 1 RPM token
 *   - estimateInputTokens() ITPM reservation
 *   - maxTokens OTPM reservation
 * After the response we reconcile against `usage`:
 *   - ITPM charged = input_tokens + cache_creation_input_tokens
 *     (cache_read_input_tokens is FREE for ITPM — the whole point of caching)
 *   - OTPM charged = output_tokens
 *   - the over-reservation is refunded / the excess debited.
 *
 * On EVERY response we clamp each bucket to min(configured, server-reported
 * limit) from the anthropic-ratelimit-{requests,input-tokens,output-tokens}-limit
 * headers, so a Tier-2 org self-raises and a Tier-1 org never breaches.
 *
 * This module is in-memory and therefore single-process-authoritative. Per the
 * design's cross-process resolution, ONLY the worker calls messages.create, so
 * one in-memory bucket is the truth (Next.js enqueues one_shot jobs instead).
 */
import { CONCURRENCY, RETRY, type Route, type RouteConfig } from "./config";

const MINUTE_MS = 60_000;

/** A single continuous-refill leaky bucket. */
class TokenBucket {
  /** Current available tokens (can briefly go negative after reconcile debit). */
  private tokens: number;
  /** Configured ceiling (capacity) — never exceeded on refill. */
  private capacity: number;
  /** Refill rate in tokens per millisecond. */
  private ratePerMs: number;
  /** Last time we advanced the refill clock. */
  private last: number;

  constructor(capacity: number) {
    this.capacity = capacity;
    this.tokens = capacity;
    this.ratePerMs = capacity / MINUTE_MS;
    this.last = Date.now();
  }

  /** Advance the continuous refill to `now`, clamped at capacity. */
  private refill(now: number): void {
    if (now <= this.last) return;
    const gained = (now - this.last) * this.ratePerMs;
    this.tokens = Math.min(this.capacity, this.tokens + gained);
    this.last = now;
  }

  /**
   * Clamp the capacity (and refill rate) to `limit`, the server-reported
   * per-minute ceiling. Only ever LOWERS below the configured value when the
   * server says we have less; raising back toward the original configured cap
   * is the caller's job (it passes min(configured, reported)).
   */
  setCapacity(limit: number): void {
    if (!Number.isFinite(limit) || limit <= 0) return;
    this.capacity = limit;
    this.ratePerMs = limit / MINUTE_MS;
    if (this.tokens > limit) this.tokens = limit;
  }

  /** Try to take `amount`. Returns true and deducts if currently available. */
  tryTake(amount: number): boolean {
    const now = Date.now();
    this.refill(now);
    if (this.tokens >= amount) {
      this.tokens -= amount;
      return true;
    }
    return false;
  }

  /** Deduct unconditionally (reconcile excess). May drive tokens negative. */
  debit(amount: number): void {
    this.refill(Date.now());
    this.tokens -= amount;
  }

  /** Refund an over-reservation, clamped at capacity. */
  refund(amount: number): void {
    this.refill(Date.now());
    this.tokens = Math.min(this.capacity, this.tokens + amount);
  }

  /**
   * Milliseconds until `amount` tokens would be available at the current rate.
   * Used to sleep precisely instead of busy-polling.
   */
  msUntil(amount: number): number {
    const now = Date.now();
    this.refill(now);
    if (this.tokens >= amount) return 0;
    const deficit = amount - this.tokens;
    return Math.ceil(deficit / this.ratePerMs);
  }

  /** Pause this bucket until `untilMs` (token-exhaustion 429 / Retry-After). */
  private pausedUntil = 0;
  pauseUntil(untilMs: number): void {
    if (untilMs > this.pausedUntil) this.pausedUntil = untilMs;
  }
  pauseRemainingMs(now: number): number {
    return this.pausedUntil > now ? this.pausedUntil - now : 0;
  }
}

/** A reservation handle returned by acquire(), settled exactly once. */
export interface Reservation {
  route: Route;
  reservedInput: number;
  reservedOutput: number;
  /** Reconcile against real usage and release the concurrency slot. */
  settle(usage: ChargeableUsage): void;
  /** Release without charging (request failed before usage was known). */
  abort(): void;
}

/** The subset of Anthropic `usage` the buckets/ledger care about. */
export interface ChargeableUsage {
  input_tokens: number;
  output_tokens: number;
  cache_creation_input_tokens?: number | null;
  cache_read_input_tokens?: number | null;
}

/** Per-route header-reported limits, if present on a response. */
export interface ReportedLimits {
  requests?: number;
  inputTokens?: number;
  outputTokens?: number;
}

const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, Math.max(0, ms)));

/** Full-jitter exponential backoff delay for attempt `n` (0-indexed). */
export function backoffDelayMs(attempt: number): number {
  const exp = Math.min(RETRY.retryCapMs, RETRY.retryBaseMs * 2 ** attempt);
  return Math.floor(Math.random() * exp);
}

/**
 * One route's throttle: three buckets + acceleration-cooldown state. Concurrency
 * is global (shared across routes) and lives on the BucketPool below.
 */
class RouteThrottle {
  readonly rpm: TokenBucket;
  readonly itpm: TokenBucket;
  readonly otpm: TokenBucket;
  /** Admission multiplier in [0,1]; lowered on an acceleration-limit 429. */
  private admission = 1;
  private admissionResetAt = 0;

  constructor(public readonly cfg: RouteConfig) {
    this.rpm = new TokenBucket(cfg.rpm);
    this.itpm = new TokenBucket(cfg.itpm);
    this.otpm = new TokenBucket(cfg.otpm);
  }

  /** Clamp every bucket to min(configured, reported) on each response. */
  clampFromHeaders(reported: ReportedLimits): void {
    if (reported.requests != null) this.rpm.setCapacity(Math.min(this.cfg.rpm, reported.requests));
    if (reported.inputTokens != null) this.itpm.setCapacity(Math.min(this.cfg.itpm, reported.inputTokens));
    if (reported.outputTokens != null) this.otpm.setCapacity(Math.min(this.cfg.otpm, reported.outputTokens));
  }

  /** Pause all three buckets until `untilMs` (token-exhaustion 429). */
  pauseUntil(untilMs: number): void {
    this.rpm.pauseUntil(untilMs);
    this.itpm.pauseUntil(untilMs);
    this.otpm.pauseUntil(untilMs);
  }

  /** Acceleration-limit 429: gradually reduce admission for a cooldown. */
  reduceAdmission(cooldownMs: number): void {
    this.admission = Math.max(0.25, this.admission * 0.5);
    this.admissionResetAt = Date.now() + cooldownMs;
  }

  /** Longest pause / refill / admission wait before this request can proceed. */
  waitMs(estInput: number, reserveOutput: number): number {
    const now = Date.now();
    // Admission throttling recovers fully after the cooldown.
    if (this.admissionResetAt && now >= this.admissionResetAt) {
      this.admission = 1;
      this.admissionResetAt = 0;
    }
    const pause = Math.max(
      this.rpm.pauseRemainingMs(now),
      this.itpm.pauseRemainingMs(now),
      this.otpm.pauseRemainingMs(now),
    );
    if (pause > 0) return pause;

    let wait = Math.max(
      this.rpm.msUntil(1),
      this.itpm.msUntil(estInput),
      this.otpm.msUntil(reserveOutput),
    );
    // While admission is reduced, add a small spacing delay so we don't slam
    // the acceleration limit again the instant the buckets refill.
    if (this.admission < 1) {
      wait = Math.max(wait, Math.ceil((MINUTE_MS / this.cfg.rpm) * (1 / this.admission - 1)));
    }
    return wait;
  }

  /** Try to atomically take 1 RPM + estInput ITPM + reserveOutput OTPM. */
  tryReserve(estInput: number, reserveOutput: number): boolean {
    const now = Date.now();
    if (
      this.rpm.pauseRemainingMs(now) > 0 ||
      this.itpm.pauseRemainingMs(now) > 0 ||
      this.otpm.pauseRemainingMs(now) > 0
    ) {
      return false;
    }
    if (!this.rpm.tryTake(1)) return false;
    if (!this.itpm.tryTake(estInput)) {
      this.rpm.refund(1);
      return false;
    }
    if (!this.otpm.tryTake(reserveOutput)) {
      this.rpm.refund(1);
      this.itpm.refund(estInput);
      return false;
    }
    return true;
  }
}

/** Circuit-breaker error for fail-fast on non-self-healing failures. */
export class CircuitOpenError extends Error {
  constructor(public readonly until: number) {
    super("anthropic gateway circuit breaker open (auth/credit failure)");
    this.name = "CircuitOpenError";
  }
}

/**
 * The pool: one RouteThrottle per route + global concurrency accounting +
 * the circuit breaker. There is exactly one of these per process.
 */
export class BucketPool {
  private throttles: Record<Route, RouteThrottle>;
  /** In-flight network calls across all routes. */
  private inFlight = 0;
  /** Of those, how many are `agent` (so we can keep a slot for one_shot). */
  private agentInFlight = 0;
  private circuitUntil = 0;

  constructor(routes: Record<Route, RouteConfig>) {
    this.throttles = {
      agent: new RouteThrottle(routes.agent),
      one_shot: new RouteThrottle(routes.one_shot),
    };
  }

  /** Is the circuit currently open (auth/credit failure cooldown)? */
  isCircuitOpen(): boolean {
    return Date.now() < this.circuitUntil;
  }

  /** Trip the breaker for `cooldownMs` (401/403/credit). */
  tripCircuit(cooldownMs: number): void {
    this.circuitUntil = Math.max(this.circuitUntil, Date.now() + cooldownMs);
  }

  /** Clamp a route's buckets from response headers (every response). */
  clampFromHeaders(route: Route, reported: ReportedLimits): void {
    this.throttles[route].clampFromHeaders(reported);
  }

  /** Pause a route's whole bucket until `untilMs` (token-exhaustion 429). */
  pauseUntil(route: Route, untilMs: number): void {
    this.throttles[route].pauseUntil(untilMs);
  }

  /** Acceleration-limit 429 (no token exhaustion): reduce admission rate. */
  reduceAdmission(route: Route, cooldownMs: number): void {
    this.throttles[route].reduceAdmission(cooldownMs);
  }

  /** Whether this route may take a concurrency slot right now. */
  private hasConcurrencySlot(route: Route): boolean {
    if (this.inFlight >= CONCURRENCY.maxConcurrency) return false;
    if (route === "agent") {
      // Reserve `reservedForOneShot` slots so agent can never fully starve Ask.
      return this.agentInFlight < CONCURRENCY.maxConcurrency - CONCURRENCY.reservedForOneShot;
    }
    return true;
  }

  private takeSlot(route: Route): void {
    this.inFlight++;
    if (route === "agent") this.agentInFlight++;
  }

  private releaseSlot(route: Route): void {
    this.inFlight = Math.max(0, this.inFlight - 1);
    if (route === "agent") this.agentInFlight = Math.max(0, this.agentInFlight - 1);
  }

  /**
   * Acquire a slot + token reservation, awaiting precise refill/concurrency
   * windows. Returns a Reservation whose settle() reconciles against real usage.
   *
   * @param route        which pool
   * @param estInput     estimated uncached input tokens to reserve (ITPM)
   * @param reserveOutput max output tokens to reserve (OTPM)
   */
  async acquire(route: Route, estInput: number, reserveOutput: number): Promise<Reservation> {
    if (this.isCircuitOpen()) throw new CircuitOpenError(this.circuitUntil);
    const t = this.throttles[route];

    // Loop: wait for tokens, wait for a concurrency slot, then reserve atomically.
    // Re-check after every sleep — another acquirer may have taken the window.
    for (;;) {
      if (this.isCircuitOpen()) throw new CircuitOpenError(this.circuitUntil);

      const tokenWait = t.waitMs(estInput, reserveOutput);
      if (tokenWait > 0) {
        await sleep(tokenWait);
        continue;
      }
      if (!this.hasConcurrencySlot(route)) {
        await sleep(25);
        continue;
      }
      if (!t.tryReserve(estInput, reserveOutput)) {
        // Lost the race to another acquirer; back off briefly and retry.
        await sleep(10);
        continue;
      }
      this.takeSlot(route);
      break;
    }

    let settled = false;
    const releaseConcurrency = () => this.releaseSlot(route);

    return {
      route,
      reservedInput: estInput,
      reservedOutput: reserveOutput,
      settle: (usage: ChargeableUsage) => {
        if (settled) return;
        settled = true;
        // ITPM: charge input + cache_creation; cache_read is FREE.
        const realInput = usage.input_tokens + (usage.cache_creation_input_tokens ?? 0);
        const realOutput = usage.output_tokens;
        reconcile(t.itpm, estInput, realInput);
        reconcile(t.otpm, reserveOutput, realOutput);
        releaseConcurrency();
      },
      abort: () => {
        if (settled) return;
        settled = true;
        // Refund the full token reservation; the call never billed.
        t.itpm.refund(estInput);
        t.otpm.refund(reserveOutput);
        releaseConcurrency();
      },
    };
  }
}

/** Refund the over-reservation, or debit the excess, against a bucket. */
function reconcile(bucket: TokenBucket, reserved: number, actual: number): void {
  if (actual < reserved) bucket.refund(reserved - actual);
  else if (actual > reserved) bucket.debit(actual - reserved);
}

export { sleep };
