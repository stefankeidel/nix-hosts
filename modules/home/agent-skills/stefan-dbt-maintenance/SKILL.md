---
name: stefan-dbt-maintenance
description: >-
  Investigate Data Platform dbt failure alerts, reproduce failing tests in the dbt
  repo, propose a fix, and open a draft GitLab MR linked to the DM ticket.
---

# Data Platform dbt maintenance

1. **Find the DM ticket first.** Search Jira project `DM` for the summary/text
   `Data Platform dbt has errors`, prioritizing the newest ticket that is open
   or In Progress and matches the alert. If there is no active match, inspect
   recent matching Done tickets for context, but ask before starting work
   against a closed ticket or inventing a DM key.
2. **Trace the production run.** In Airflow, inspect recent runs of
   `data_platform_dbt` around the alert time. Find the failed `dbt` task, read
   its logs (paginate fully), and record the failing test/model names, result
   counts, and relevant error/query details. Distinguish data-test failures
   from compilation, database, or infrastructure errors.
3. **Reproduce in the dbt repository.** Assume the clone to shared
   `DATA_PLATFORM_DEV` has run. Run only the relevant tests first, using the
   repo's configured dev target, e.g.:
   `uv run dbt test --select <failed-test-selector> --target <dev-target>`
   Never target production. If the clone appears missing/stale or the failure
   cannot be reproduced, report that rather than changing test logic to silence
   the alert.
4. **Fix and validate.** Check the repo status before editing; preserve unrelated
   work. Create `fix/DM-XXXX/<description-stub>` for the selected ticket. Make
   the smallest correct fix, then rerun the failing tests and relevant checks.
5. **Push and open a draft MR.** Push the branch and create a draft MR in the
   dbt repo. Include the DM link, Airflow run, exact failure evidence, root
   cause, proposed fix, and validation commands/results in the description.
   Link the ticket; do not claim it is fixed until validation supports that.

