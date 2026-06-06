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
import { morningRouter } from "./morning";
import { aiRouter } from "./ai";
import { syncRouter } from "./sync";
import { connectorRouter } from "./connector";
import { captureRouter } from "./capture";
import { tripRouter } from "./trip";
import { turnRouter } from "./turn";

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
  morning: morningRouter,
  ai: aiRouter,
  sync: syncRouter,
  connector: connectorRouter,
  capture: captureRouter,
  trip: tripRouter,
  turn: turnRouter,
});

export type AppRouter = typeof appRouter;
