# Testing

No test suite or test framework is set up yet. Do not add a test framework (e.g. RSpec, Jest) without the user's approval, because it is a new dependency.

## What must be tested once implemented

From `docs/design_doc.md` section 7:

- **Map structure**: JSON Schema validation of LLM output, plus detection of cycles in `map_paths`, `sub_node_paths` and `sub_nodes`, unknown references, and orphan nodes.
- **Node reuse**: reused nodes are not duplicated, keep their progress, added sub nodes show up in other maps, and another user's nodes cannot be referenced.
- **Compass**: for maps in different progress states (nothing started, partly completed, several `in_progress`, only sub nodes completed, all completed) and graphs with branches and merges, check `current_node_id`, `candidates` (contents and order), and `is_goal_reached`. For shared nodes: known nodes drop out of candidates and satisfy incoming paths, nodes started in this map stay candidates, and `started_map_id = NULL` is not known.
- **Progress update**: only the acting map's current position moves; goal reached with an origin node returns a suggestion and never auto-completes it.
- **Difficulty mapping**: ライト / スタンダード / ディープ produce the intended `max_depth` and other prompt limits.
- **Streaming (E2E)**: with an LLM stub that streams a fixed fixture node by node, drop the SSE connection mid-generation and check that the job keeps running to `ready`; reconnecting with the same `GET /api/maps/:id/generation` resends all saved nodes, then new ones, then `done`; resent nodes are not drawn twice (upsert by node ID); nodes received so far still show correctly, also after reloading S-03; no compass before `done`; a job failure ends with `error` and the failed view; deleting a generating map in another tab ends with `deleted`, a move to S-01 and the deletion notice (`docs/design_doc.md` sections 4.2.9, 4.3.1, 4.4).
- **Map deletion**: nodes used by other maps keep their progress; unreferenced nodes are deleted.
- **Security**: API keys are absent from frontend responses and source maps; the opt-out setting is always sent.

## LLM calls in tests

Unit tests must not call the real LLM API. Use fixed JSON fixtures for LLM responses.
