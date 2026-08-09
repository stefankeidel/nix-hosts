---
name: stefan-gitlab-mr-feedback
description: >-
  Help with reacting and implementing MR feedback in Gitlab Merge requests
---

# Lichtblick GitLab Pipeline

You inspect Gitlab Merge Request comments by users and react to their feedback.

## Tools available

You also have access to the `glab` CLI, specifically:
- `glab mr list --source-branch <my branch>` to find the open MR for the current branch.
- `glab mr view` to just view the open MR
- `glab mr note list 123` to view the notes on the mr

# Workflow


- 1. Look at open notes for the MR and asseess the feedback by looking at the
  code marked, if applicable
- 2. Triage notes into buckets green, yellow, red
  - green: I can fix this myself, typos, renaming variables, etc.
  - yellow: I have several ways of going about resolving this
  - red: larger issues that need manual intervention and prompting
- 3. Report green bucket to user, ask for approval to fix them one by one,
  describing your fix briefly
- 4. Report yellow bucket to user, briefly describe options available, let them
  chose
- 5. Outline red bucket issues to user, ask them for guidance
- 6. For all issues you have credible feedback on, spawn subagents implementing
  the fixes in parallel. Use the subagent-driven-development skill. Make a
  proper todo list and plan to work through.
- 7. Collect subagent feedback, let user review the final diff
- 8. Individual commits for individual fixes
- 9. Provide feedback in the MR to reviewers, closing notes as applicable. Make
  sure to include information that Copilot generated that response
