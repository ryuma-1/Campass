---
paths:
  - "backend/**"
---

# LLM Integration

Rules for code that calls the LLM API. Based on `docs/basic-design.md` sections 6.4 and 7.2.

## API keys

- The service's LLM API key lives only in backend environment variables (`.env` → container env). It must never appear in frontend code, API responses, or source maps.
- A learner's own key (F-020, `docs/basic-design.md` sections 7.1 and 7.2) is sent once from S-05 (`PUT /api/llm_credential`; `PUT` and `DELETE` are Cookie session only, Bearer → `401`, so the CLI cannot change it) and stored in `user_llm_credentials.api_key` with Active Record Encryption (non-deterministic). Never return it in any response (only `provider`, `model`, `api_key_last4`, `verified_at`), never log it (`filter_parameters` includes `api_key`; keep it out of exception messages and error bodies), never pass it as a job argument, and send it to Gemini in the `x-goog-api-key` header, never in the URL.
- The root `.env` reaches the `backend` container only, through Compose `env_file`; `frontend` and `cli` never get it. The file itself is not mounted, so `Dotenv.load` in `backend/gemini_comu.rb` finds nothing and the key comes from `ENV`. Rails code should read keys from `ENV`.

## Structured output

- Map generation must use JSON Schema structured output so the response format is enforced. Do not parse free-form text. #26 compared it with tool calling and chose structured output for now; tool calling may be added later if it turns out to be needed (prototype: branch `prototype/llm-tool-calling`, never merged).
- Each main node has `ref`, `existing_node_id` (reuse) or `title` + `summary` (new), `from` (incoming paths), `importance_score` (0–1, orders and highlights compass candidates within a group), `is_start` (the starting node), nested `sub_nodes`, and `detour` (or `null`). Full schema: `docs/basic-design.md` section 6.4.2.
- The prompt includes the user's existing nodes (IDs, titles, sub node IDs) so the LLM reuses them. Send only the current user's nodes.
- A parse failure is fixed the same way as a validation error (below).

## Map output rules (basic-design 6.3, 6.4)

From the prototype (branch `prototype/llm-map-generation`, never merged). These also hold if tool calling is added later (#26).

- Every main node except the first connects by a path to a main node output before it. Check it as soon as the node arrives, so the saved part is always one connected map.
- Exactly one main node has `is_start: true` (F-021): the node that best matches `maps.start_text` (a reused node is fine). Ask only for the prerequisites the starting node directly needs; nodes neither before nor after it are allowed. `node_count_target` counts every main node, prerequisites included.
- `from` lists only prerequisites the learner cannot understand the node without. Nodes that can be learned in parallel stay parallel; do not chain them.
- For validation at generation time only, the last main node in the output counts as the goal node. A main node that cannot reach it by paths is a validation error; the prompt forbids it too. No order or goal node is stored (goal reached still means every main node is completed). Whether to keep this goal-node rule is decided while implementing (design-doc section 6).
- Tell the LLM "at least N and at most M main nodes" from `node_count_target`; a count outside the range is a validation error. Also give the sub node count guide for the difficulty (not validated).
- Do not force three-way branches. Gemini expresses parallel learning with several main nodes that have an empty `from` instead.
- A reused node may be written with its full contents. Saving ignores existing `sub_nodes` / `sub_node_paths`, adds only new ones, and never deletes any. A new path that makes a cycle is a validation error.

Specific to structured output (Gemini):

- The schema expands `sub_nodes` nesting down to `max_depth`.
- Never enforce counts with JSON Schema `minItems` / `maxItems`: Gemini rejects the schema with `400 INVALID_ARGUMENT` as nesting gets deeper and the values get larger.
- Fixing errors (basic-design 6.4.4): never save a node with an error. Before the first main node is saved, regenerate, sending the previous output and the errors as a continuation of the conversation (the same prompt repeats the same mistake). Once any node is saved, close the stream and ask for the remaining nodes only, sending the saved nodes (IDs, titles, paths, starting node) and the errors; never delete or rewrite saved nodes. Regenerations and continuations together are at most 2; then `failed` (`invalid_map` / `parse_failed`).
- Still open (design-doc section 6), to settle with the user while implementing: keeping the goal node, limiting path direction (e.g. outputting the starting node first), too many or too few main nodes, and running past the limit of 2.

## Calling the LLM (basic-design 7.2)

- Put an abstract LLM interface in the backend with two jobs only: (1) generate: take a system prompt, the conversation and a JSON Schema (or tools), and stream text fragments back; (2) verify a key and model (F-020): say whether the key is valid and the model is usable with it, per provider (Gemini: `GET /v1beta/models`, following `nextPageToken`; it runs no model, so it costs nothing; quota and billing are not checked). The key and model are given to it from outside; it does not know whether they are the service's or a learner's. Node splitting, validation and saving stay outside it and are shared across LLMs. The generation job takes it from outside, so tests use a fake.
- The first implementation calls Gemini directly with Faraday (`streamGenerateContent?alt=sse`, `systemInstruction`, `responseJsonSchema`). Do not use the `google-genai` gem (0.1.1) for this: it handles neither streaming nor `systemInstruction`. Keep it in the Gemfile.
- The service's key uses the one provider chosen by `LLM_PROVIDER` (default `gemini`) and `LLM_MODEL` (default `gemini-3.1-flash-lite`). Service API keys are per provider (now `GEMINI_API_KEY`). A learner's own key may use any implemented provider and only the models listed per provider in a config file (`GET /api/llm_providers`); free model names are rejected.
- Which key (F-020, `docs/basic-design.md` section 7.2): if the learner has a `user_llm_credentials` row, every LLM call for that learner (map generation, goal and starting-node suggestions) uses that key, provider and model; otherwise the service's. If the learner's key fails, never fall back to the service's key and never retry (failure codes: `../meta/error.md`). The generation job reads the credential once when it starts and keeps it to the end; changing or deleting the key mid-generation does not affect that job. When `maps.start_text` is NULL, the job first asks for starting-node suggestions with no input and saves the recommended title to `start_text`, with the same key (basic-design 6.4.6).
- Before adding a second provider (OpenAI / Anthropic), check its schema and count handling with a prototype as was done for Gemini. Consider LiteLLM (as a proxy) at that point, not before.

## Streaming

- Never forward partial token fragments to the frontend; only a complete, saved node reaches the SSE stream (see `backend.md` for the buffering and job mechanics).
- There is no cancel; deleting the map stops the job (`docs/basic-design.md` section 6.4.6, ADR 0004).

## Prompt safety

- Keep the system prompt separate from user input. Never put user free text into the instruction part of the prompt.
- In production, use only an LLM API key from a plan whose terms say inputs and outputs are not used for training (Gemini: a Cloud project with billing enabled). Do not add a per-request opt-out setting or a check before sending; the deploy steps check the key instead. Development (test data only) is exempt. A learner's own key (F-020) is outside this promise: their inputs follow the learner's own terms with that provider, and S-05 says so (`docs/basic-design.md` section 7.2).

## Prompt templates

Prompt templates should be managed separately from the code deploy cycle, so they can be tuned and A/B tested without a redeploy (`docs/basic-design.md` section 7.2).
