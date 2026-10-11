# LLM Integration

Rules for code that calls the LLM API. Based on `docs/design_doc.md` sections 4.2.4, 4.3.2 and 6.

## API keys

- The LLM API key lives only in backend environment variables (`.env` → container env). They must never appear in frontend code, API responses, or source maps.
- The root `.env` reaches the `backend` container only, through Compose `env_file`; `frontend` and `cli` never get it. The file itself is not mounted, so `Dotenv.load` in `backend/gemini_comu.rb` finds nothing and the key comes from `ENV`. Rails code should read keys from `ENV`.

## Structured output

- Map generation must use JSON Schema structured output (or tool calling) so the response format is enforced. Do not parse free-form text.
- Each main node has `ref`, `existing_node_id` (reuse) or `title` + `summary` (new), `from` (incoming paths), `importance_score` (0–1, used to highlight compass candidates), nested `sub_nodes`, and `detour` (or `null`). Full schema: `docs/design_doc.md` section 4.2.4.
- The prompt includes the user's existing nodes (IDs, titles, sub node IDs) so the LLM reuses them. Send only the current user's nodes.
- If parsing fails, retry at most 2 times in the backend.

## Map output rules (design_doc 4.2.2, 4.2.4)

From the prototype (branch `prototype/llm-map-generation`, never merged). These hold for both structured output and the tool-calling approach under discussion in #26.

- `from` lists only prerequisites the learner cannot understand the node without. Nodes that can be learned in parallel stay parallel; do not chain them.
- The last main node is the goal. A main node that cannot reach the goal by paths is a validation error; the prompt forbids it too.
- Tell the LLM "at least N and at most M main nodes" from `node_count_target`; a count outside the range is a validation error. Also give the sub node count guide for the difficulty (not validated).
- Do not force three-way branches. Gemini expresses parallel learning with several start nodes instead.
- A reused node may be written with its full contents. Saving ignores existing `sub_nodes` / `sub_node_paths`, adds only new ones, and never deletes any. A new path that makes a cycle is a validation error.

Specific to structured output (Gemini):

- The schema expands `sub_nodes` nesting down to `max_depth`.
- Never enforce counts with JSON Schema `minItems` / `maxItems`: Gemini rejects the schema with `400 INVALID_ARGUMENT` as nesting gets deeper and the values get larger.
- On regeneration (max 2), send the previous output and the validation errors as a continuation of the conversation; the same prompt repeats the same mistake. When regeneration may run once nodes are saved is open (design_doc section 9); settle it with the user first.

## Calling the LLM (design_doc 4.3.2)

- Put an abstract LLM interface in the backend. Its only job: take a system prompt, the conversation and a JSON Schema (or tools), and stream text fragments back. Node splitting, validation and saving stay outside it and are shared across LLMs. The generation job takes it from outside, so tests use a fake.
- The first implementation calls Gemini directly with Faraday (`streamGenerateContent?alt=sse`, `systemInstruction`, `responseJsonSchema`). Do not use the `google-genai` gem (0.1.1) for this: it handles neither streaming nor `systemInstruction`. Keep it in the Gemfile.
- Choose the LLM with `LLM_PROVIDER` (default `gemini`) and `LLM_MODEL` (default `gemini-3.1-flash-lite`). Only one provider at a time. API keys are per provider (now `GEMINI_API_KEY`).
- Before adding a second provider (OpenAI / Anthropic), check its schema and count handling with a prototype as was done for Gemini. Consider LiteLLM (as a proxy) at that point, not before.

## Streaming

- The backend reads the LLM token stream and buffers it until one node's JSON is complete. It then saves that node to the DB; the SSE endpoint reads saved nodes from the DB and sends each as one event.
- Never forward partial token fragments to the frontend.
- Generation runs in a background job and continues when the user leaves or the CLI is stopped (`docs/design_doc.md` section 4.2.9, ADR 0004). There is no cancel; deleting the map stops the job.

## Prompt safety

- Keep the system prompt separate from user input. Never put user free text into the instruction part of the prompt.
- Always attach the opt-out setting (no training on user data) to every LLM request (`docs/basic_design.md` section 5.4).

## Prompt templates

Prompt templates should be managed separately from the code deploy cycle, so they can be tuned and A/B tested without a redeploy (`docs/design_doc.md` section 8).
