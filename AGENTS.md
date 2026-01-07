# Task Tracker

- [x] Audit model defaults and API guards across portfolio_index/portfolio_core/portfolio_manager.
- [x] Fix rate limiter ETS races and full-text search table/content handling.
- [x] Clean up examples (agent max-iterations, telemetry handler warnings).
- [x] Review portfolio_coder docs (20260106 missing; reviewed 20260105/portfolio_integration/design.md) and align portfolio_manager/docs/examples; verify DB/Neo4j status.
- [x] Add portfolio_manager migration to enable pg_trgm extension.
- [x] Fix portfolio_index Neo4j examples to ensure Boltx starts; rerun examples/tests.
- [x] Add mocked and live-tagged tests for gemini/claude/codex/openai adapters; align examples to cover all four providers.
- [x] Fix Codex SDK model fallback + embedder registry startup; rerun tests/examples.
- [x] Add Supertester 0.5.0 test dependency for isolation tooling review.
- [x] Refactor portfolio_index/portfolio_core/portfolio_manager tests to use Supertester case isolation.
- [x] Remove sleep-based test timing in portfolio_manager; add safe router shutdown helper.
- [x] Fix async Supertester ETS registry overrides causing rate limiter flakiness.
