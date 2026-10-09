# Backend Architecture

Ruby on Rails 7.1 in API mode. Design from `docs/basic_design.md` section 2.3 and `docs/design_doc.md` sections 4.2–4.3. Not implemented yet (no Rails app has been generated).

## Layers

```mermaid
graph TD
    FE[Frontend]

    subgraph BE[Backend: Rails API]
        C["Controller layer<br/>REST responses, SSE streaming"]
        S["Service layer<br/>map generation, node reuse,<br/>compass, prompt building"]
        M["Model layer<br/>ActiveRecord"]
    end

    DB[(MySQL)]
    LLM[LLM API]

    FE -->|REST| C
    C -.->|SSE| FE
    C --> S
    S --> M
    M --> DB
    S -->|streaming, JSON Schema| LLM
```

| Layer | Responsibility |
| :--- | :--- |
| Controller | Accepts API requests and returns normal or SSE responses. No business logic. |
| Service | Business logic and all LLM API calls. |
| Model | MySQL access through ActiveRecord. |

## Map generation pipeline

```mermaid
graph LR
    P[Prompt with the user's existing nodes] --> A[LLM token stream]
    A --> B[Buffer until one node's JSON is complete]
    B --> C{Valid?}
    C -->|yes| D[Save node or reuse existing,<br/>map_nodes / paths / sub_nodes / detour]
    C -->|no| R[Retry request, max 2] --> A
    D --> A
    A -->|stream ends| G[Mark map ready]
    D -.->|read from DB| F[SSE: one node event per saved node]
```

The pipeline runs in a background job (ActiveJob `:async`) started by `POST /api/maps`, not in the SSE request, so it continues when the client disconnects (`docs/design_doc.md` section 4.2.9, ADR 0004):

- Save one node per transaction. Lock the `maps` row first (`SELECT … FOR UPDATE`); if the map is gone, close the LLM stream, log, and stop quietly; if it is no longer `generating`, stop without saving. Update `maps.generation_heartbeat_at` after each save.
- On an exception, set `status = failed` and `generation_error_code`. Log the details; never store the exception message.
- A `generating` map whose heartbeat is older than the limit (5 minutes to start with) is set to `failed` / `timed_out` by the SSE loop and by map-reading APIs.
- The SSE controller never receives nodes from the job. On every connection it sends all saved nodes, then polls the DB for new ones, and ends with `done`, `error` or `deleted`.

See `llm-integration.md` for LLM call rules and `../meta/error.md` for failure handling.

## API endpoints

Defined in `docs/design_doc.md` section 4.3.1 (response examples are there too).

| Endpoint | Purpose |
| :--- | :--- |
| `GET /api/maps` / `POST /api/maps` | List / create maps (F-012). `POST` takes the goal, difficulty, and `origin_node_id` or `detour_id` (F-017, F-006), creates the map as `generating` and starts the generation job (F-011). |
| `DELETE /api/maps/:id` / `GET /api/maps/:id/deletion_preview` | Delete a map (also while `generating`; locks the `maps` row first) / preview what deletion affects. |
| `POST /api/goal_suggestions` | Goal candidates for vague input (F-002). Called before the map exists. |
| `GET /api/maps/:id/generation` (SSE) | Watch generation (F-011): all saved nodes as `node` events, then new ones, then `done`, `error` or `deleted`. Reconnectable; no `Last-Event-ID`. |
| `GET /api/maps/:id` | `status` and `error`, main nodes, paths, detour entrances, origin links, and `compass` (only when `ready`). |
| `GET /api/maps/:mapId/nodes/:nodeId` | Node detail: summary, progress, this map's detour, other maps it appears in. |
| `GET /api/nodes/:id/sub_nodes` | Drill-down (F-007): sub nodes and the paths among them (shared, no map). |
| `PATCH /api/maps/:mapId/nodes/:nodeId/progress` | Update progress (F-010); updates the map's current position and `started_map_id`; returns `compass` and `origin_completion_suggestion`. |

## Core algorithms

- **No linearization.** `display_order` and the topological-sort step were removed (F-005, F-008 are 廃止). Do not add a stored order.
- **Node reuse (F-015, design_doc 4.2.4)**: send the user's existing nodes (with their sub nodes) to the LLM; it reuses them by ID instead of creating duplicates, and may add sub nodes to a reused node. For a map made from an origin node, its new main nodes also become sub nodes of the origin node. Never reuse another user's nodes.
- **Compass (F-013, design_doc 4.2.8)**: over the map's main nodes, recomputed on every progress update, never stored.
  - Current position: `maps.current_node_id`, set when a main node is started or completed in that map.
  - Known node: `completed`, or `in_progress` with `started_map_id` set to another map (`NULL` counts as this map).
  - Candidates: not completed, not known, and every incoming `map_paths` source is completed or known. Sort by `importance_score` desc, then `id`. Return all of them.
  - Goal reached: every main node completed; return `is_goal_reached: true` and empty `candidates`. Never auto-complete the origin node; return a suggestion instead.
  - Sub node progress is recorded but ignored by the compass.
- **Drill-down (F-007)**: sub nodes come from `sub_nodes` and are the same in every map.
- **Difficulty (F-003)**: ライト / スタンダード / ディープ map to `max_depth` and `node_count_target`.
- **Map deletion**: cascade `map_nodes`, `map_paths`, `detours`; delete a node only when no map and no node references it.
