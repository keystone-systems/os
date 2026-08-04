Stage: ingest

Read `$HOME/.keystone/sources.json`, `TASKS.yaml`, and `PROJECTS.yaml`.
Create `TASKS.yaml` with `tasks: []` if it does not exist.
Treat the order in `PROJECTS.yaml` as the project priority order.
Create a task only for an actionable source item.
Ignore informational messages, automated notifications, marketing, closed issues, and closed pull requests.
Use the source URL as `source_ref` for issue and pull request items.
Use `email-<id>-<sender>` as `source_ref` for email items.
Do not create a task if its `source_ref` already exists.
Create each new task with `name`, `description`, `status`, `source`, and `source_ref`.
Set each new task status to `pending`.
Set `project` when the source maps to a project in `PROJECTS.yaml`.
Use a descriptive kebab-case task name.
Preserve every existing task and all of its fields.
Append new tasks after existing tasks.
Do not add another top-level key.
If a source message contains `ping`, create a task that replies with `pong`.
For an email subject `[ping] <tag>`, require the reply subject `Re: [pong] <tag>`.
Require the reply body to contain `pong`.
Write valid YAML.
