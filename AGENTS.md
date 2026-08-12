# Development workflow: maker-checker

Every code change must use two separate delegated agents.

1. Delegate implementation to a Maker and require it to use `$maker`. The Maker reads the applicable `AGENTS.md` files, makes the smallest correct change, runs relevant tests, and summarizes its work. The Maker must not commit.
2. After the Maker finishes, delegate an independent review to a different Checker and require it to use `$checker`. The Checker is read-only and reports correctness, security, edge-case, error-handling, test, and convention issues.
3. If the Checker finds any Critical or Important issue, delegate the fixes to a Maker. Then delegate another full review to a Checker. Repeat this fix and review cycle until the Checker returns `APPROVE`.

Never let the Maker review its own work. Never let the Checker modify files. A Checker approval is not permission to commit. Create a commit only when the user explicitly requests one.
