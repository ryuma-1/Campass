# Error Handling

## General

- Before proposing a fix, explain the root cause.
- Never swallow errors silently. A `rescue` must log the error or re-raise it.
- Rescue specific exception classes (e.g. `Faraday::TimeoutError`) before any generic `rescue => e`.

## LLM / streaming failures

- A response that fails JSON parsing is retried at most 2 times (see `llm-integration.md`). After that, return an explicit error to the client instead of saving partial or invalid data as if it succeeded.
- If generation fails partway, do not roll back. Keep the saved nodes, set the map to `failed` with `generation_error_code`, and let the SSE send `error`. Saved and sent nodes stay consistent because the SSE only sends what is in the DB (`docs/basic-design.md` section 6.4.6). User-facing messages come from the code → message table, never from the exception.
- If a learner's own LLM key fails (F-020), fail with `user_api_key_invalid` or `user_api_key_quota_exceeded`; never fall back to the service's key and never retry (`docs/basic-design.md` section 7.2).
- LLM output that breaks the map rules (cycles in paths or sub nodes, unknown references) is a validation error. Do not silently drop or fix those paths.
