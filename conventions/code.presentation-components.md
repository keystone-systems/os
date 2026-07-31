<!-- RFC 2119: MUST, MUST NOT, SHOULD, SHOULD NOT, MAY -->

# Convention: Presentation Components (code.presentation-components)

## Principle

UI components are gloves — shaped by the interface, filled with data at render time.
A presentation component declares _what_ it displays via props; it never decides _where_
the data comes from. This separation enables parallel frontend/backend development,
early stakeholder feedback with fixture data, and visual regression testing via Storybook.

## Component Structure

1. Every UI view MUST be split into a **presentation component** (pure rendering) and a **container** (data fetching, mutations, routing).
2. Presentation components MUST receive all data and callbacks through props — they MUST NOT call APIs, read from context, or access global state directly.
3. Presentation components MUST define an explicit props interface (e.g., `UserProfileProps`) that serves as the data contract between frontend and backend.
4. The props interface SHOULD use domain types, not raw API response shapes — map API responses in the container, not the presentation layer.
5. Loading, empty, and error states MUST be expressible through props (e.g., `loading?: boolean`, `error?: string`, nullable data fields) so every state is renderable in isolation.

## Fixture Data

6. Every presentation component MUST have a co-located Storybook story file (`ComponentName.stories.tsx`).
7. Stories MUST cover the primary happy path and SHOULD cover edge cases (empty state, error state, overflow text, maximum items).
8. Fixture data SHOULD live in story files or shared fixture modules — it MUST NOT be imported into production code.
9. Fixture data SHOULD be realistic (use faker or domain-appropriate values), not placeholder strings like `"test"` or `"Lorem ipsum"`.
10. When a backend API contract changes, the props interface MUST be updated first, then fixtures, then the container — the presentation component adapts automatically.

## Composition Stories

11. Beyond individual component stories, the project SHOULD include **composition stories** (e.g., `Layouts.stories.tsx`) that assemble multiple presentation components into page-level views.
12. Composition stories MUST use only the public component API (props) — they MUST NOT mock internal implementation details.
13. Composition stories SHOULD represent real user flows: sign-in forms, list pages, detail views, data tables.

## Container / Presentation Boundary

14. Containers MUST be thin — their only job is to fetch data, transform it to match the props interface, and pass it down.
15. Containers MUST NOT contain layout or styling logic — that belongs in the presentation component.
16. Server components (e.g., Next.js RSC) and client wrappers MAY serve as containers; the presentation component itself SHOULD remain a plain function component with no framework-specific data hooks.

## Parallel Development Workflow

17. Frontend work MAY proceed before the backend API exists — fixture data fills the glove until real data is available.
18. When working without a backend, the container SHOULD import fixture data behind a feature flag or environment check, then swap to the real API call when ready.
19. Stakeholder reviews SHOULD use Storybook or a fixture-driven deploy so feedback focuses on UI/UX, not backend availability.

## Testing

20. Presentation components SHOULD be tested via Storybook interaction tests or snapshot tests against their stories — not by mounting the full container with mocked APIs.
21. Container tests SHOULD verify data transformation and prop mapping, not re-test rendering.
