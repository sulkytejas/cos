// Flat ESLint config. The load-bearing rule here is the gateway invariant:
// `@anthropic-ai/sdk` may be imported ONLY from src/server/anthropic — that
// directory holds the single `new Anthropic()` and the only ANTHROPIC_API_KEY
// read (SERVER_ARCHITECTURE.md §4.b). Banning the import everywhere else makes
// the one-choke-point invariant enforceable in CI instead of by convention.
import tseslint from "typescript-eslint";
import reactHooks from "eslint-plugin-react-hooks";

const banAnthropicSdk = {
  name: "ban-anthropic-sdk-outside-gateway",
  files: ["**/*.ts", "**/*.tsx", "**/*.mts", "**/*.cts"],
  // The gateway and its helpers are the ONLY place the SDK may be imported.
  ignores: ["src/server/anthropic/**"],
  // Parse TypeScript/TSX so the rule evaluates instead of hitting parse errors.
  languageOptions: {
    parser: tseslint.parser,
    parserOptions: {
      ecmaVersion: "latest",
      sourceType: "module",
      ecmaFeatures: { jsx: true },
    },
  },
  rules: {
    "no-restricted-imports": [
      "error",
      {
        paths: [
          {
            name: "@anthropic-ai/sdk",
            message:
              "Import the AI gateway (src/server/anthropic/gateway.ts) instead. " +
              "@anthropic-ai/sdk may only be used inside src/server/anthropic — " +
              "it is the single choke point that holds ANTHROPIC_API_KEY and the " +
              "only caller of messages.create (SERVER_ARCHITECTURE.md §4.b).",
          },
        ],
        patterns: [
          {
            group: ["@anthropic-ai/sdk", "@anthropic-ai/sdk/*"],
            message:
              "@anthropic-ai/sdk is restricted to src/server/anthropic — route " +
              "all Anthropic calls through the gateway.",
          },
        ],
      },
    ],
  },
};

// Register the react-hooks plugin so pre-existing
// `// eslint-disable-next-line react-hooks/exhaustive-deps` directives in the
// component tree resolve to a real rule (previously provided by next lint).
const reactHooksPlugin = {
  name: "react-hooks",
  files: ["**/*.tsx", "**/*.jsx"],
  plugins: { "react-hooks": reactHooks },
  languageOptions: {
    parser: tseslint.parser,
    parserOptions: {
      ecmaVersion: "latest",
      sourceType: "module",
      ecmaFeatures: { jsx: true },
    },
  },
  rules: {
    "react-hooks/rules-of-hooks": "error",
    "react-hooks/exhaustive-deps": "warn",
  },
};

export default [
  {
    // Build output and deps are never linted.
    ignores: ["node_modules/**", ".next/**", "dist/**", "ios/**"],
  },
  banAnthropicSdk,
  reactHooksPlugin,
];
