# LLM Integration

Rules for code that calls the LLM API. Based on `docs/design_doc.md` sections 4.2.4, 4.3.2 and 6.

## API keys

- The LLM API key lives only in backend environment variables (`.env` → container env). They must never appear in frontend code, API responses, or source maps.
- `gemini_comu.rb` loads `.env` through `dotenv`; Rails code should read keys from `ENV`.

## Structured output

- Map generation must use JSON Schema structured output (or tool calling) so the response format is enforced. Do not parse free-form text.
- Each main node has `ref`, `existing_node_id` (reuse) or `title` + `summary` (new), `from` (incoming paths), `importance_score` (0–1, used to highlight compass candidates), nested `sub_nodes`, and `detour` (or `null`). Full schema: `docs/design_doc.md` section 4.2.4.
- The prompt includes the user's existing nodes (IDs, titles, sub node IDs) so the LLM reuses them. Send only the current user's nodes.
- If parsing fails, retry at most 2 times in the backend.

## Streaming

- The backend reads the LLM token stream and buffers it until one node's JSON is complete. It then saves that node to the DB; the SSE endpoint reads saved nodes from the DB and sends each as one event.
- Never forward partial token fragments to the frontend.
- Generation runs in a background job and continues when the user leaves or the CLI is stopped (`docs/design_doc.md` section 4.2.9, ADR 0004). There is no cancel; deleting the map stops the job.

## Prompt safety

- Keep the system prompt separate from user input. Never put user free text into the instruction part of the prompt.
- Always attach the opt-out setting (no training on user data) to every LLM request (`docs/basic_design.md` section 5.4).

## Prompt templates

Prompt templates should be managed separately from the code deploy cycle, so they can be tuned and A/B tested without a redeploy (`docs/design_doc.md` section 8).
