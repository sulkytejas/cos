import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";
import {
  format,
  formatDistanceToNowStrict,
  parseISO,
  isValid,
  differenceInCalendarDays,
} from "date-fns";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function fmtDate(value: string | null | undefined, pattern = "MMM d, yyyy") {
  if (!value) return "";
  const d = value.length === 10 ? parseISO(value) : new Date(value);
  if (!isValid(d)) return "";
  return format(d, pattern);
}

export function fmtRange(start: string | null, end: string | null) {
  if (!start && !end) return "ongoing";
  if (start && end) {
    const s = parseISO(start);
    const e = parseISO(end);
    if (isValid(s) && isValid(e) && s.getFullYear() === e.getFullYear()) {
      return `${format(s, "MMM d")} – ${format(e, "MMM d, yyyy")}`;
    }
    return `${fmtDate(start)} – ${fmtDate(end)}`;
  }
  if (start) return `from ${fmtDate(start)}`;
  return `until ${fmtDate(end)}`;
}

export function fmtRelative(value: string | null | undefined) {
  if (!value) return "";
  const d = new Date(value);
  if (!isValid(d)) return "";
  return formatDistanceToNowStrict(d, { addSuffix: true });
}

export function daysUntil(value: string | null | undefined) {
  if (!value) return null;
  const d = value.length === 10 ? parseISO(value) : new Date(value);
  if (!isValid(d)) return null;
  return differenceInCalendarDays(d, new Date());
}

export function dueClass(dueDate: string | null | undefined) {
  const d = daysUntil(dueDate);
  if (d === null) return "text-ink-faint";
  if (d < 0) return "text-ember";
  if (d <= 3) return "text-ember";
  if (d <= 14) return "text-ink-secondary";
  return "text-ink-faint";
}
