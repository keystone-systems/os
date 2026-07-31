# Convention: Cloudflare Workers (tool.cloudflare-workers)

## Configuration

1. Worker configuration MUST live in `wrangler.jsonc` (preferred) or `wrangler.toml` at the project root.
2. The `name` field in wrangler config MUST match the Cloudflare Workers service name.
3. Bindings (KV, D1, R2, etc.) MUST be declared in the wrangler config, not set at runtime.
4. Binding names SHOULD be descriptive and uppercase (e.g., `SESSIONS_KV`, `ASSETS_BUCKET`).
5. `compatibility_date` SHOULD be set to a recent date and updated periodically.

## Secrets and Variables

6. Secrets MUST NOT be hardcoded — use `wrangler secret put <NAME>` to set them from the server.
7. Wrangler secrets MUST be set from a machine with `wrangler` CLI access (typically the server or a developer workstation).
8. For projects with GitHub Actions CI, secrets needed by the deploy workflow MUST also be configured as GitHub Actions secrets/variables:

   ```bash
   # GitHub Actions secrets (encrypted, for tokens/passwords)
   gh secret set SECRET_NAME --repo OWNER/REPO --env production

   # GitHub Actions variables (plain text, for URLs/config)
   gh variable set VAR_NAME --repo OWNER/REPO --env production --body "value"
   ```

9. After configuring missing secrets, failed GitHub Actions workflows SHOULD be rerun:
   ```bash
   gh run rerun $RUN_ID --repo OWNER/REPO
   ```

See `process.continuous-integration` for general CI gating and log handling rules.

## Development

10. Local development SHOULD use `wrangler dev` for testing.
11. Workers MUST handle errors gracefully and return appropriate HTTP status codes.
12. Workers SHOULD log structured JSON for observability.

## Deployment

13. Production deployments SHOULD go through GitHub Actions (not manual `wrangler deploy`) for auditability.
14. The deploy workflow MUST use the `production` environment for secret scoping.
15. Workers MUST be deployed via `wrangler` from the project's dev shell.

## CF Workers Builds (Git Integration)

16. Cloudflare Workers Builds MAY be enabled for automatic preview deployments on PRs.
17. Workers Builds runs only the configured build command (typically `pnpm build`) — it does NOT support multi-step workflows, git submodules, or custom TypeScript runners (`tsx`).
18. If a project requires build-time steps beyond `pnpm build` (e.g., `sync-docs`, submodule init), those steps MUST either be incorporated into the `build` script in `package.json` with `|| true` fallback, or production deploys MUST go through GitHub Actions.
19. Build scripts that depend on submodules or `tsx` MUST fail gracefully in CF Workers Builds:
    ```json
    "build": "node scripts/sync.mjs || true; next build"
    ```

## Preview Environments

20. CF Workers Builds creates preview deployments automatically for each push to a PR branch.
21. Preview URLs follow these patterns:
    - **Branch preview**: `https://{branch-slug}-{project-name}.{account}.workers.dev`
    - **Commit preview**: `https://{commit-hash-prefix}-{project-name}.{account}.workers.dev`
22. Branch names are slugified: `feat/my-feature` → `feat-my-feature`.
23. Preview URLs are posted by the Cloudflare bot as a PR comment with a markdown table containing both branch and commit URLs.
24. To extract preview URLs programmatically:
    ```bash
    gh pr view $PR_NUM --repo OWNER/REPO --json comments --jq '.comments[].body' | grep -o 'https://[^ ]*workers.dev[^ ]*'
    ```
25. Preview deployments from CF Workers Builds are limited — they reflect only what the build command produces. If submodules or multi-step builds are needed, the preview will show a partial build.

## Limits

26. Workers MUST respect the CPU time limit (10ms free, 30s paid) — avoid synchronous heavy computation.
27. Response bodies SHOULD be streamed for large payloads.

## Next.js on Cloudflare Workers (OpenNext.js)

See `tool.nextjs` for general Next.js conventions (App Router, Server Components, data fetching).

28. Next.js apps MUST use the [OpenNext.js Cloudflare adapter](https://opennext.js.org/cloudflare) to deploy on CF Workers.
29. The project MUST include `open-next.config.ts` at the root configuring the adapter.
30. The wrangler config MUST set `main` to `.open-next/worker.js` and `assets.directory` to `.open-next/assets`.
31. Build scripts MUST use `opennextjs-cloudflare build` for production builds:
    ```json
    "preview": "opennextjs-cloudflare build && opennextjs-cloudflare preview",
    "deploy": "opennextjs-cloudflare build && opennextjs-cloudflare deploy"
    ```
32. R2 bindings SHOULD be configured for incremental cache storage if the app uses ISR or caching.
33. `nodejs_compat` compatibility flag MUST be enabled for Node.js API access.
34. Image optimization SHOULD use the `images` binding if available.

## GitHub Actions Deploy Workflow

35. The deploy workflow MUST checkout with `submodules: recursive` if the project uses git submodules.
36. The workflow SHOULD cache `.next/cache` for faster builds:
    ```yaml
    - uses: actions/cache@v4
      with:
        path: ${{ github.workspace }}/.next/cache
        key: ${{ runner.os }}-nextjs-${{ hashFiles('**/pnpm-lock.yaml') }}-${{ hashFiles('**/*.ts', '**/*.tsx') }}
    ```
37. Custom build steps (sync scripts, migrations, dataload) MUST run after `pnpm install` and before the Next.js build.
38. The workflow trigger paths SHOULD include `.gitmodules` and `.submodules/**` if the project uses submodules.

See `tool.nix-devshell` for flake.nix and direnv setup conventions.

## Project Setup Checklist

When setting up a new CF Workers project (or onboarding to an existing one), verify:

1. `wrangler.jsonc` exists with correct worker name and bindings
2. `flake.nix` includes `wrangler` and `nodejs` in the dev shell
3. `.envrc` with `use flake` for direnv integration
4. GitHub Actions secrets/variables configured for the `production` environment
5. Wrangler secrets set via `wrangler secret put` from the server
6. CF Workers Builds git integration enabled in Cloudflare dashboard (for preview deploys)
7. For Next.js: `open-next.config.ts` present, `opennextjs-cloudflare` in devDependencies
