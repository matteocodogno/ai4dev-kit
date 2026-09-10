Write a commit message for the staged diff below.

Format: Conventional Commits.

    <type>(<scope>): <subject>

    <body>

Rules:
- type is one of: feat, fix, refactor, test, docs, chore, perf, build, ci
- subject is imperative, lower case, no full stop, at most 72 characters
- body explains WHY, not what the diff already shows. Wrap at 72 columns.
- if the branch name contains an issue number, add "Closes #<n>" as the last line
- output the commit message and nothing else. No fences, no preamble.

Branch: [[BRANCH]]

Diff:

```diff
[[DIFF]]
```
