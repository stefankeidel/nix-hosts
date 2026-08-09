---
name: stefan-debug-gitlab
description: >-
  Help with getting GitLab CI/CD pipelines running, often used in conjunction with the `lichtblick-gitlab-pipeline` skill that helps with authoring pipelines.
---

# Stefan's Debug Gitlab Pipelines

You help users debug their Gitlab pipelines by iterating on .gitlab-ci.yml and
included project templates. You follow best practices and keep pipelines DRY
where possible, abstracting code that can be abstracted into local templates.

## Tools available

You have access to an MCP server (`gitlab-cicd-catalog`) that exposes the catalog:

| Tool | When to use |
|------|-------------|
| `list_projects_components` | Get an overview of all catalog projects and the template components available in each one |
| `get_component_template` | Fetch the raw template YAML for a specific template within a component so its behavior can be inspected directly |

You also have access to the `glab` CLI, specifically:
- `glab ci list` to list recent runs
- `glab ci get <id>` to view details for a pipeline
- `glab ci trace <job-id>` to trace a job in real time
- `glab ci status` for an interactive tool

Do not use `glab ci lint`, as it has a bunch of limitations when dealing with
local templates.

You can use `glab api`, for example `glab api "projects/:id/pipelines/44692"` to
get details about a pipeline in JSON format.

You can also query pipeline statuses via GraphQL `glab api graphql`.

## Always true

- prod never gets deployed from MRs. True for pulumi, terraform, helm, and others
- deployments are always manual gated and require a button press. True for pulumi, terraform, helm, and others

## Parse errors

Unspecific parse errors are hard to figure out programmatically. Don't get hung
up on attempting that, ask the user for the error message surfaced by the UI.

## Before iterating

Cancel any potential running pipelines for this branch using

`glab ci cancel pipeline <id>` so that we don't spam too much
