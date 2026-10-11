# Project Guidance

## General approach
- Inspect existing patterns before making changes.
- Prefer the smallest change that solves the problem.
- Do not introduce new abstractions unless the existing design clearly requires them.
- Do not refactor unrelated code.
- Preserve current architecture and naming conventions.
- Explain the intended change before making broad or architectural edits.

## Rails conventions
- Follow Rails autoloading and Zeitwerk conventions.
- Avoid manual requires for application code unless there is a clear reason.
- Keep controllers thin.
- Prefer service objects for domain/business logic where that pattern already exists.
- Keep API responses stable unless explicitly asked to change them.
- Preserve current authentication, authorization, and entitlement boundaries.

## Data and entitlements
- Rails is the server source of truth for entitlements.
- RevenueCat or external subscription providers are inputs, not the authoritative domain model.
- Preserve idempotency in subscription, entitlement, and webhook flows.
- Be careful around tier transitions and downgrade behavior.

## External services
- Preserve caching, stale fallback, timeout, and single-flight protections around external APIs.
- Avoid increasing API call volume without explicit justification.
- Treat Google Directions, UDOT, and weather integrations as failure-prone external dependencies.

## Testing
- Run the narrowest relevant tests first.
- Add tests for new behavior and regressions.
- Do not weaken or remove tests merely to make a change pass.
- Run `bin/rails zeitwerk:check` after changes affecting loading, namespaces, or file structure.
- Report any warnings separately from failures.

## Safety
- Do not modify production credentials, secrets, environment files, or deployment configuration unless explicitly asked.
- Do not run destructive database commands.
- Do not create migrations unless the task requires a schema change.
- Ask before making broad cross-cutting changes.

## Workflow
Save all review, research, planning, and completion summaries as descriptive `.txt` files in the root-level `research/` directory, and link the saved file in the response.
Stage new task-created files with `git add` before handing work back. Do not stage unrelated files, and do not commit or push unless explicitly requested.

Before changing code:
1. Identify the relevant files.
2. Explain the current pattern.
3. State the proposed change.
4. Note any risks or assumptions.

After changing code:
1. Run relevant tests.
2. Run lint/static checks when appropriate.
3. Summarize exactly what changed.
4. Call out anything not fully verified.
