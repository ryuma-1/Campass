# Error Handling

## General

- Before proposing a fix, explain the root cause.
- Never swallow errors silently. A `rescue` must log the error or re-raise it.
- Rescue specific exception classes (e.g. `Google::Genai::APIError`) before any generic `rescue => e`.

## LLM / streaming failures

- A response that fails JSON parsing is retried at most 2 times (see `llm-integration.md`). After that, return an explicit error to the client instead of saving partial or invalid data as if it succeeded.
- If generation fails partway, do not roll back. Keep the saved nodes, set the map to `failed` with `generation_error_code`, and let the SSE send `error`. Saved and sent nodes stay consistent because the SSE only sends what is in the DB (`docs/design_doc.md` section 4.2.9). User-facing messages come from the code → message table, never from the exception.
- LLM output that breaks the map rules (cycles in paths or sub nodes, unknown references) is a validation error. Do not silently drop or fix those paths.
