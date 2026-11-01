---
name: stefan-dbt-maintenance
description: >-
  Investigate Data Platform dbt failure alerts, reproduce failing tests in the dbt
  repo, propose a fix, and open a draft GitLab MR linked to the DM ticket.
---

# Data Platform dbt maintenance

1. **Find the DM ticket first.** Search Jira project `DM` for the summary/text
   `Data Platform dbt has errors`, prioritizing the newest ticket that is open
   or In Progress and matches the alert. If multiple matching tickets are found,
   consolidate all investigation, code, and MR work under the newest matching
   active ticket; comment on every other matching ticket with the canonical
   ticket key and a link or summary of the consolidated work. If there is no
   active match, inspect recent matching Done tickets for context, but ask
   before starting work against a closed ticket or inventing a DM key.
2. **Set ownership and start work.** Read each matching active ticket and use
   `assign_issue_to_me` for any that are unassigned; preserve existing assignees
   and leave closed tickets unchanged. For the canonical ticket, use
   `list_issue_transitions` to find the transition whose destination is
   `In Progress`, then apply its ID with `transition_issue`. Skip the transition
   if the ticket is already In Progress. Keep investigation and status movement
   consolidated on the canonical ticket, not the older duplicates. Respect the
   interactive confirmations; if assignment or transition is unavailable or
   denied, report the blocker rather than claiming it succeeded.
3. **Trace the production run.** In Airflow, inspect recent runs of
   `data_platform_dbt` around the alert time. Find the failed `dbt` task, read
   its logs (paginate fully), and record the failing test/model names, result
   counts, and relevant error/query details. Use read-only Snowflake queries to
   inspect affected `DATA_PLATFORM_DEV` relations and verify the failing rows.
   Distinguish data-test failures from compilation, database, or infrastructure
   errors.
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

