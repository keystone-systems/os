## Next.js

## App Router

1. New pages MUST use the App Router (`app/` directory), not the Pages Router.
2. Route handlers MUST live in `app/api/` using `route.ts` files.
3. Layouts MUST be used for shared UI — do NOT duplicate layout markup across pages.
4. Loading and error states SHOULD use `loading.tsx` and `error.tsx` conventions.

## Components

5. Components MUST default to Server Components. Add `"use client"` only when client-side interactivity is required (event handlers, hooks, browser APIs).
6. Client Components SHOULD be as small as possible — push `"use client"` to the leaf.
7. Data fetching MUST happen in Server Components or route handlers, not in Client Components.

## Data Fetching

8. Server-side data fetching SHOULD use `fetch()` with Next.js caching/revalidation options.
9. Mutations MUST use Server Actions or route handlers, not client-side `fetch` to external APIs.
10. You MUST NOT expose secrets or API keys in Client Components or client-side bundles.

## Styling

11. Styling approach SHOULD be consistent within a project (Tailwind, CSS Modules, or styled-components — pick one).
12. Global styles MUST be imported in the root layout, not in individual pages.

## Performance

13. Images MUST use `next/image` for automatic optimization.
14. Third-party scripts SHOULD use `next/script` with appropriate loading strategy.
15. Dynamic imports (`next/dynamic`) SHOULD be used for heavy client-only components.
