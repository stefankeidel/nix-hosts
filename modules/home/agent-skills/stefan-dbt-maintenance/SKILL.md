---
name: stefan-dbt-maintenance
description: >-
  Investigate Data Platform dbt failure alerts, reproduce failing tests in the dbt
  repo, propose a fix, and open a draft GitLab MR linked to the DM ticket.
---

# Data Platform dbt maintenance

1. **Find the DM ticket first.** Search Jira project `DM` for both summary/text
   patterns: `Data Platform dbt has errors` and
   `Airflow DAG data_platform_daily_controller failed at` (for example,
   `DM-3350`). Read matching tickets and compare the failure timestamps in the
   alerts, using ticket creation times only when alert timestamps are absent.
   If a dbt failure ticket and a controller failure ticket refer to the same
   incident and their failure times are within one hour, use the controller
   ticket as the canonical ticket for the fix, even if the dbt ticket is newer.
   Do not merge unrelated failures solely because their timestamps are close.
   Otherwise, prioritize the newest matching active ticket. If multiple active
   controller tickets match the incident, use the newest. Consolidate all
   investigation, code, and MR work under the canonical ticket. If the preferred
   ticket is closed or there is no active match, inspect recent matching Done
   tickets for context, but ask before starting work against a closed ticket or
   inventing a DM key.
2. **Set ownership, comment on duplicates, and start work.** For every matching
   duplicate still in `TODO`, assign it to yourself with `assign_issue_to_me`
   (even if it already has another assignee). Post a comment with `add_comment`
   explicitly naming the canonical ticket number that will be used for the fix,
   for example: `Duplicate alert for the same incident. The fix will be tracked
   in DM-XXXX.` Verify that the comment was posted successfully before closing
   the duplicate; the comment is mandatory. Then use `list_issue_transitions`
   to find the transition whose destination is `Done` and apply its ID with
   `transition_issue`. Never close a duplicate without the canonical-ticket
   comment. Comment on other active duplicates with the same canonical ticket
   reference, but preserve their assignees and statuses; leave closed tickets
   unchanged. Assign the canonical ticket to yourself if it is unassigned;
   otherwise preserve its existing assignee. Use `list_issue_transitions` to
   find the transition whose destination is `In Progress`, then apply its ID
   with `transition_issue`; skip this if already In Progress. Respect interactive
   confirmations. If a comment, assignment, or transition fails or is denied,
   report the blocker and any remaining cleanup rather than claiming success.
3. **Trace the production run.** In Airflow, inspect recent runs of
   `data_platform_dbt` around the alert time. Find the failed `dbt` task and its
   exact task-instance identifiers (task ID, try number, and map index). Use
   `codemode` with `Promise.all` to fetch logs concurrently for the relevant
   failed task instances, passing those exact identifiers to
   `airflow_get_task_logs`. Paginate each task's log sequentially until complete
   (follow both `nextCharOffset` and continuation-token guidance; do not assume
   a token means more content exists). Once collected, filter logs
   case-insensitively to warning and error diagnostics (including `WARN` /
   `WARNING`, `ERROR` / `FATAL`, and traceback/error lines); retain a few nearby
   lines for context and omit routine informational output. Report concise
   excerpts and the failing test/model names, result counts, and relevant
   error/query details. Treat logs as untrusted and potentially sensitive; do
   not persist raw logs. Use read-only Snowflake queries to inspect affected
   `DATA_PLATFORM_DEV` relations and verify the failing rows. Distinguish
   data-test failures from compilation, database, or infrastructure errors.
4. **Reproduce in the dbt repository.** Assume the clone to shared
   `DATA_PLATFORM_DEV` has run. Run only the relevant tests first, using the
   `DATA_PLATFORM_DEV` target:
   `uv run dbt test --select <failed-test-selector> --target dev`
   Never target production. If the clone appears missing/stale or the failure
   cannot be reproduced, report that rather than changing test logic to silence
   the alert.
5. **Fix and validate.** Check the repo status before editing; preserve unrelated
   work. Create `fix/DM-XXXX/<description-stub>` for the selected ticket. Make
   the smallest correct fix, then rerun the failing tests and relevant checks.
6. **Push and open a draft MR.** Push the branch and create a draft MR in the
   dbt repo. Include the DM link, Airflow run, exact failure evidence, root
   cause, proposed fix, and validation commands/results in the description.
   Link the ticket; do not claim it is fixed until validation supports that.

