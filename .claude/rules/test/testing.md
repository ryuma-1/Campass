---
paths:
  - "backend/test/**"
  - "cli/**/*_test.go"
  - "frontend/**/*.{test,spec}.*"
  - "e2e/**"
---

# Testing

No test suite or test framework is set up yet. Do not add a test framework (e.g. RSpec, Jest) without the user's approval, because it is a new dependency.

What to test for each feature is defined in `docs/basic-design.md` section 8.

## General rules

- **API shape**: the only source of the API's shape is `api/openapi.yaml` (`../meta/docs.md`). Backend (producer) tests check requests and responses against it with `committee`. Frontend and CLI (consumer) tests generate types from it (`openapi-typescript`, `oapi-codegen -generate types`) and run every fixture through the Prism validating proxy, so a mismatched fixture or request fails the test. Content correctness (compass order, reuse, …) is for backend tests and E2E, not schema checks. Fixtures are written per test and scene, never shared as common examples.
- **LLM calls**: unit tests must never call the real LLM API; use fixed JSON fixtures for LLM responses. A behaviour never run against the real LLM, even in the prototype, needs a manual check with real calls after implementing (`docs/basic-design.md` section 8).
- **Time-dependent behaviour**: advance time with `travel_to` / `travel` (`ActiveSupport::Testing::TimeHelpers`); never make a test actually wait.
- **Concurrency / row locks**: fix the execution order instead of waiting for a race — pause one thread right after it takes the lock (a test-only hook, e.g. `Concurrent::Event`), let the other proceed, then resume and check the order of effects, in both directions. Row-lock tests need the real MySQL (Compose `db`), so turn off `use_transactional_tests` for them only and clean up the data they create themselves.
