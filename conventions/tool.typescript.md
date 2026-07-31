## TypeScript

## Type Safety

1. `strict: true` MUST be enabled in `tsconfig.json`.
2. You MUST NOT use `any` — use `unknown` and narrow, or define a proper type.
3. Function return types SHOULD be inferred unless the function is exported or the type is non-obvious.
4. Prefer `interface` for object shapes and `type` for unions, intersections, and mapped types.

## Error Handling

5. Errors at system boundaries (user input, external APIs) MUST be handled explicitly.
6. Internal function calls SHOULD NOT wrap every call in try/catch — let errors propagate to boundaries.
7. Custom error classes SHOULD extend `Error` and set `name` for reliable `instanceof` checks.

## Imports & Modules

8. Imports MUST use ES modules (`import`/`export`), not CommonJS (`require`/`module.exports`).
9. Barrel files (`index.ts` re-exports) SHOULD be avoided — import directly from the source module.
10. Circular imports MUST NOT exist — restructure or extract shared types to break cycles.

## Style

11. Variables and functions MUST use `camelCase`.
12. Types and interfaces MUST use `PascalCase`.
13. Constants MAY use `SCREAMING_SNAKE_CASE` for true compile-time constants.
14. Prefer `const` over `let`. Never use `var`.

## Testing

15. Tests MUST be co-located with source files or in a `__tests__/` directory at the same level.
16. Test files MUST use `.test.ts` or `.spec.ts` suffix.
17. Tests SHOULD test behavior, not implementation details.
