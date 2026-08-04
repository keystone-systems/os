Stage: prioritize

Read `TASKS.yaml` and `PROJECTS.yaml`.
Treat the order in `PROJECTS.yaml` as the project priority order.
Reorder pending tasks by project priority.
Put pending tasks without a project after project tasks.
Do not reorder completed, blocked, error, or in-progress tasks.
Assign a model to each pending task that has no model.
Use `haiku` for simple mechanical work.
Use `sonnet` for standard multi-step work.
Use `opus` for advanced architecture, multi-system debugging, or novel work.
Preserve an existing model.
Do not change any field except `model`.
Do not create or remove a task.
Write valid YAML.
