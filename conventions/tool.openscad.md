## OpenSCAD

## Project Structure

1. Projects SHOULD use Python to generate OpenSCAD code for parametric flexibility.
2. The main entry point MUST produce a `.scad` file that can be rendered with `openscad`.
3. Generated `.scad` files SHOULD be committed for review, not just the Python source.

## Modeling

4. All dimensions MUST use millimeters as the base unit.
5. Parametric values MUST be defined as variables at the top of the file or as function arguments.
6. Magic numbers MUST NOT appear in geometry operations — use named variables.
7. Complex models SHOULD be decomposed into modules.

## Rendering

8. Preview (`F5`) SHOULD be used during development; full render (`F6`) for final output.
9. STL exports MUST use sufficient `$fn` or `$fa`/`$fs` for smooth curves.
10. You SHOULD set `$fn` globally at the top of the file for consistent resolution.

## Style

11. Module names MUST use `snake_case`.
12. Variables MUST use `snake_case`.
13. Each module SHOULD have a comment describing its purpose and parameters.
