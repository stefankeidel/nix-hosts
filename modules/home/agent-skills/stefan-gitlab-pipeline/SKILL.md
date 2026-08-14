---
name: stefan-gitlab-pipeline
description: >-
  Configure, review, and troubleshoot Lichtblick GitLab CI/CD pipelines by
  inspecting the shared component catalog through Pi's GitLab tools. Use when
  adding or changing pipeline jobs, selecting catalog components, validating
  component inputs, or diagnosing CI behavior. Do not use an MCP server.
---

# Stefan GitLab Pipeline

Use Pi's GitLab tools to inspect Lichtblick's live CI/CD component catalog and then configure or troubleshoot pipelines from what the catalog actually contains.

## Non-negotiable rules

- **Do not use MCP.** Use `gitlab_api` and the dedicated GitLab tools available in Pi.
- **Always inspect the live catalog before writing pipeline YAML from scratch.** A maintained component likely exists for common jobs such as versioning, linting, builds, and deployments.
- Fetch and read the applicable `template.yml`; do not infer behavior from a project or template name.
- Prefer catalog components over hand-written jobs. Write custom YAML only after confirming that no catalog component fits, and state that explicitly.
- Pin component includes to the latest applicable **major version**, for example `@2` or `@3`. Never use `@~latest`.
- Follow the repository's existing include style and keep configuration DRY.
- Never expose credentials or tokens. GitLab tools handle authentication.

## Catalog locations

Inspect projects in both groups:

- `lichtblick/scopes/gitlab/components`
- `lichtblick/scopes/data/gitlab`

The original catalog service treats every project directly in these groups as a possible catalog project. Components are directories under `templates/`, and each component template is stored at:

```text
templates/<template-name>/template.yml
```

## Reproduce the catalog operations with `gitlab_api`

### 1. List catalog projects

Call both group endpoints, preferably in parallel:

```text
GET /groups/lichtblick%2Fscopes%2Fgitlab%2Fcomponents/projects
GET /groups/lichtblick%2Fscopes%2Fdata%2Fgitlab/projects
query: { per_page: 100, simple: true }
```

Preserve each project's `id`, `name`, `path`, `path_with_namespace`, `description`, and `default_branch` (use `main` only if no default is returned).

### 2. List a project's available components

For each relevant project, inspect its `templates` tree:

```text
GET projects/:project/repository/tree
project: <path_with_namespace>
query: { path: "templates", ref: <default_branch>, per_page: 100 }
```

Only entries with `type: "tree"` are component/template names. A missing `templates` path means that project has no available components.

Do not fetch every project tree if the user's need clearly narrows the candidates. If an overview is requested, inspect all projects and parallelize independent reads.

### 3. Determine the version

Inspect tags for each candidate project:

```text
GET projects/:project/repository/tags
project: <path_with_namespace>
query: { order_by: "updated", sort: "desc", per_page: 20 }
```

Select the latest suitable stable release and derive its major version by removing a leading `v` and taking the leading integer. Use that major in the include, such as `@2`. Ignore prereleases unless the user explicitly asks for one. If no reliable major can be determined, ask the user rather than using `@~latest`.

### 4. Fetch the actual template

URL-encode the complete repository file path:

```text
GET projects/:project/repository/files/templates%2F<template-name>%2Ftemplate.yml/raw
project: <path_with_namespace>
query: { ref: <default_branch> }
```

Read the entire YAML, especially:

- `spec.inputs`: names, types, defaults, descriptions, options, and required inputs
- generated job names and stages
- image, script, services, artifacts, cache, and dependencies/needs
- `rules`, environment handling, and deployment behavior
- expected CI/CD variables or secrets

If behavior depends on referenced local files, fetch those files too. Consult the catalog project's README when the template alone does not explain intended usage.

## Workflow

1. Understand the requested stage, behavior, environments, and trigger conditions.
2. Inspect the target repository's existing `.gitlab-ci.yml` and related local includes.
3. Query both catalog groups and identify plausible projects/components.
4. Fetch candidate templates and tags; inspect their real behavior and inputs.
5. Choose the maintained component that best fits. Explain briefly why it fits.
6. Compose or edit the `include: component:` entry using the full catalog path and a major-version pin. Preserve the repository's established style.
7. Supply inputs whose values are known from repository context. Clearly list required inputs or CI/CD variables that remain unknown and ask the user for them; do not invent secrets or environment-specific values.
8. Check the Data pipeline convention below and flag intentional exceptions.
9. Validate local syntax/diffs. Run `gitlab_ci_lint` for the project after changing CI configuration when possible.
10. For troubleshooting, inspect the included template first, then use `gitlab_pipeline_status` and `gitlab_job_logs` as needed. Distinguish component behavior, consumer configuration, and runtime failure.

## Include shape

Use the component's real project path, template name, and latest suitable major discovered above:

```yaml
include:
  - component: gitlab.lichtblick.app/<path-with-namespace>/<template-name>@<major>
    inputs:
      # Values required by spec.inputs
```

Do not copy this blindly: preserve any include host/path convention already used by the target repository and verify the exact component path from the live catalog.

## Data pipeline convention

Data at Lichtblick uses `dev` and `prod` environments:

- Merge request pipelines (`$CI_PIPELINE_SOURCE == "merge_request_event"`) run lint, test, and preview jobs for both dev and prod, without deploying.
- Default-branch pushes (`$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH`) deploy to both dev and prod.

When composing or reviewing a Data pipeline, check that it follows this pattern. Jobs or stages outside these triggers are exceptions and should be called out, not silently normalized.

## Troubleshooting checklist

- Confirm the included project, template name, and major version exist in the live catalog.
- Compare supplied `inputs` exactly with the template's current `spec.inputs`.
- Check whether job names are interpolated or changed by inputs.
- Evaluate component `rules` together with the consumer pipeline source, branch, MR state, and variables.
- Check stage availability, `needs`, environment names, protected variables, and runner/tag requirements.
- Lint the effective configuration where possible before triggering a new pipeline.
- Do not mutate GitLab state or trigger pipelines without the confirmation required by the GitLab tools.
