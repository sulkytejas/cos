import { router } from "../trpc";
import { chapterRouter } from "./chapter";
import { todoRouter } from "./todo";
import { decisionRouter } from "./decision";
import { entryRouter } from "./entry";
import { briefRouter } from "./brief";
import { proposalRouter } from "./proposal";
import { eventRouter } from "./event";
import { watcherRouter } from "./watcher";
import { signalRouter } from "./signal";

export const appRouter = router({
  chapter: chapterRouter,
  todo: todoRouter,
  decision: decisionRouter,
  entry: entryRouter,
  brief: briefRouter,
  proposal: proposalRouter,
  event: eventRouter,
  watcher: watcherRouter,
  signal: signalRouter,
});

export type AppRouter = typeof appRouter;
