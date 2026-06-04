import { fetchRequestHandler } from "@trpc/server/adapters/fetch";
import { appRouter } from "@/server/routers/_app";
import { createContext } from "@/server/trpc";

const handler = (req: Request) =>
  fetchRequestHandler({
    endpoint: "/api/trpc",
    req,
    router: appRouter,
    // Resolve the Authorization: Bearer header to a userId (§4.f). No fail-open:
    // an absent/unknown/revoked token leaves userId null and protectedProcedure 401s.
    createContext: () => createContext({ headers: req.headers }),
  });

export { handler as GET, handler as POST };
