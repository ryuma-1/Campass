# Overall Architecture

Design as defined in `docs/basic_design.md` section 2 and `docs/design_doc.md` sections 3–4. Nothing below is implemented yet; when implementing, follow these decisions unless the design docs are updated first. Frontend and backend internals are in `frontend.md` and `backend.md`.

## System diagram

```mermaid
graph LR
    User[User / Browser]

    subgraph FE[Frontend: React SPA]
        FEApp[学習マップ + compass UI]
    end

    subgraph BE[Backend: Rails API]
        BEApp[Controllers / Services / Models]
    end

    DB[(MySQL 8.0)]
    LLM[External LLM API]
    EMB[External Embedding API]

    User -->|HTTPS| FEApp
    FEApp -->|REST| BEApp
    BEApp -.->|SSE: one event per node| FEApp
    BEApp -->|ActiveRecord| DB
    BEApp -->|streaming request, opt-out on| LLM
    BEApp -->|embedding request| EMB
```

- The frontend talks only to the backend. Only the backend calls the LLM and Embedding APIs, and only the backend holds their API keys.
- Syllabus generation is streamed: LLM tokens → backend buffers until one node is complete → save to DB → one SSE event to the frontend.

## Main flow (design_doc 3.2)

```mermaid
sequenceDiagram
    actor U as User
    participant FE as Frontend
    participant BE as Backend
    participant LLM as LLM API
    participant EMB as Embedding API
    participant DB as MySQL

    U->>FE: free-text interest (F-001)
    FE->>BE: POST /api/notebooks/:id/goal_suggestions
    BE->>LLM: is the goal specific enough?
    LLM-->>BE: 3 goal candidates if vague (F-002)
    U->>FE: choose goal + difficulty (F-003)
    FE->>BE: POST /api/notebooks/:id/assessment
    BE->>LLM: generate 3-5 questions (F-004)
    U->>FE: answer questions
    FE->>BE: POST /api/notebooks/:id/syllabus (SSE)
    BE->>LLM: generate syllabus (streaming, JSON Schema)
    loop each completed node
        LLM-->>BE: tokens
        BE->>DB: save node + edges
        BE->>EMB: embed main-route node
        BE->>DB: create proposed cross-notebook link if similar
        BE-->>FE: SSE node event (+ link_proposal event if similar)
    end
    BE->>DB: mark notebook ready
    FE->>BE: GET /api/notebooks/:id/map
    BE-->>FE: depth-0 graph + links + compass
    U->>FE: pick a compass candidate, update progress
    FE->>BE: PATCH /api/nodes/:id/progress
    BE-->>FE: updated compass
```

## Shared data model

The syllabus is a DAG stored as relational node + edge tables, not in a graph DB (`docs/design_doc.md` section 5.1).

- `syllabus_nodes`: `route_type` (`main` / `sub`), `depth_level`, `parent_node_id`, `related_main_node_id`, `importance_score` (LLM-assigned, 0–1), `embedding` (main-route nodes only).
- `syllabus_edges`: prerequisite relations between nodes.
- `cross_notebook_links`: links between nodes in different notebooks of the same user, with status `proposed` / `accepted` / `rejected` and a unique constraint per node pair.

Full table definitions: `docs/design_doc.md` section 4.1.2 (the source of truth; `docs/basic_design.md` section 4 is only an overview).

The 学習マップ shows this graph as-is. There is **no linear roadmap view and no stored order** (`display_order` and the linearization algorithm were removed in design_doc v0.5.0). Do not reintroduce them.

## Concept: map + compass

The app's concept (and its name, Campass) is "spread out a map and check the compass": the 学習マップ shows the whole syllabus, and a **compass** points from the learner's **current position** to **every node the learner can study now** (F-013, `docs/design_doc.md` section 4.2.8).

- The "map" is a metaphor only. Nodes have no coordinates; the 学習マップ is drawn as a network graph.
- Current position = the `in_progress` node (latest `updated_at` if several); otherwise the most recently completed node (`completed_at`); otherwise none (start point).
- Compass candidates = incomplete main-route nodes whose `required` main-route prerequisites are all completed. All candidates are shown; the user chooses. `importance_score` only decides which candidate is highlighted.
- The compass is derived from `syllabus_edges` + `progress_statuses` each time. It is not stored.
- `sub` nodes (寄り道) are never the current position or the compass target.

## Undecided

The screen flow for the 学習マップ and for presenting cross-notebook-link proposals, and what happens when a user leaves during generation, are still undecided (`docs/design_doc.md` section 9). Confirm with the user before implementing them.
