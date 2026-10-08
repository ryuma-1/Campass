# Testing

No test suite or test framework is set up yet. Do not add a test framework (e.g. RSpec, Jest) without the user's approval, because it is a new dependency.

## What must be tested once implemented

From `docs/design_doc.md` section 7:

- **Syllabus structure**: JSON Schema validation of LLM output, plus detection of cycles (invalid DAG edges) and orphan nodes.
- **Compass**: for syllabi in different progress states (nothing started, partly completed, several `in_progress`, only sub nodes completed, all completed) and graphs with branches, merges, and `supplementary` edges, check `current_node_id`, `candidates` (contents and order), and `is_goal_reached`.
- **Difficulty mapping**: ライト / スタンダード / ディープ produce the intended `max_depth` and other prompt limits.
- **Streaming (E2E)**: reconnect / resume when the SSE connection drops, and nodes received so far still show correctly.
- **Cross-notebook links**: regression dataset of similar / dissimilar title pairs around the threshold; no proposals across users; no duplicate proposals for a pair.
- **Link status flow**: `PATCH /api/cross_notebook_links/:id` moves `proposed → accepted / rejected`, and a rejected pair is not proposed again.
- **Security**: API keys are absent from frontend responses and source maps; the opt-out setting is always sent.

## LLM calls in tests

Unit tests must not call the real LLM or Embedding API. Use fixed JSON fixtures for LLM responses.
