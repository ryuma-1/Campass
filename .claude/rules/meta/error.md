# Error Handling

## General

- Before proposing a fix, explain the root cause.
- Never swallow errors silently. A `rescue` must log the error or re-raise it.
- Rescue specific exception classes (e.g. `Google::Genai::APIError`) before any generic `rescue => e`.

## LLM / streaming failures

- A response that fails JSON parsing is retried at most 2 times (see `llm-integration.md`). After that, return an explicit error to the client instead of saving partial or invalid data as if it succeeded.
- If streaming fails partway, the nodes already saved and the nodes already sent to the frontend must stay consistent. The design notes that rollback here is complex (`docs/design_doc.md` section 5.2); confirm the approach with the user before implementing it.
- LLM output that breaks DAG rules (cycles, references to unknown prerequisite ids) is a validation error. Do not silently drop or fix those edges.
