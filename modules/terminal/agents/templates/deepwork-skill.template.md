# DeepWork workflow manager

Execute multi-step workflows with quality gate checkpoints.

## Terminology

A **job** is a collection of related **workflows**. Users may use the terms
"job" and "workflow" interchangeably. Use `get_workflows` to discover the
currently available jobs and workflows before deciding.

## How to use

1. Call `get_workflows` to discover available workflows.
2. Call `start_workflow` with the chosen `goal`, `job_name`, and `workflow_name`.
3. Follow the step instructions returned by the MCP server.
4. Call `finished_step` with the outputs when a step is complete.
5. Handle the response: `needs_work`, `next_step`, or `workflow_complete`.

## Intent parsing

- Explicit workflow: `/deepwork <workflow>` means start that workflow.
- General request: `/deepwork <goal>` means infer the best workflow from `get_workflows`.
- No context: `/deepwork` alone means ask the user to choose from available workflows.
