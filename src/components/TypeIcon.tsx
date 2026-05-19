import { Plane, Building2, Rocket, Briefcase, Repeat, Circle } from "lucide-react";
import type { ChapterType } from "@/db/schema";

export function TypeIcon({
  type,
  className,
}: {
  type: ChapterType;
  className?: string;
}) {
  const props = { className: className ?? "h-4 w-4" };
  switch (type) {
    case "trip":
      return <Plane {...props} />;
    case "move":
      return <Building2 {...props} />;
    case "project":
      return <Briefcase {...props} />;
    case "launch":
      return <Rocket {...props} />;
    case "recurring":
      return <Repeat {...props} />;
    default:
      return <Circle {...props} />;
  }
}

export function typeLabel(type: ChapterType): string {
  return type.toUpperCase();
}
