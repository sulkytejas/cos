import { router } from "../trpc";
import { chapterRouter } from "./chapter";
import { todoRouter } from "./todo";
import { decisionRouter } from "./decision";
import { entryRouter } from "./entry";

export const appRouter = router({
  chapter: chapterRouter,
  todo: todoRouter,
  decision: decisionRouter,
  entry: entryRouter,
});

export type AppRouter = typeof appRouter;
