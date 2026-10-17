---
paths:
  - "backend/**"
  - "frontend/**"
  - "cli/**"
---

# Overall Architecture

Design as defined in `docs/basic-design.md` sections 2 and 6. Nothing below is implemented yet; when implementing, follow these decisions unless the design docs are updated first. Frontend and backend internals are in `frontend.md` and `backend.md`. Domain terms (マップ, ノード, 道, メインノード, サブノード, 寄り道, 元ノード, 既知ノード, …) follow `GLOSSARY.md`; decisions behind the model are in `docs/adr/`.

## System diagram

```mermaid
graph LR
    User[User / Browser]

    subgraph FE[Frontend: React SPA]
        FEApp[Map screen + compass UI]
    end

    subgraph BE[Backend: Rails API]
        BEApp[Controllers / Services / Models]
    end

    DB[(MySQL 8.0)]
    LLM[External LLM API]

    User -->|HTTPS| FEApp
    FEApp -->|REST| BEApp
    BEApp -.->|SSE: one event per node| FEApp
    BEApp -->|ActiveRecord| DB
    BEApp -->|streaming request, no-training plan key| LLM
```

- The frontend talks only to the backend. Only the backend calls the LLM API and holds its key.
- Map generation is streamed: LLM tokens → backend buffers until one node is complete → save to DB → one SSE event to the frontend.
- Generation runs as a background job (ActiveJob `:async`), detached from the request, and continues when the client disconnects. The job only writes to the DB; the SSE endpoint reads saved nodes from the DB, so it can be reconnected any time (`docs/basic-design.md` section 6.4.6, ADR 0004).

## Main flow (basic-design 6.1)

```mermaid
sequenceDiagram
    actor U as User
    participant FE as Frontend
    participant BE as Backend
    participant LLM as LLM API
    participant DB as MySQL

    U->>FE: free-text interest (F-001)
    FE->>BE: POST /api/goal_suggestions
    BE->>LLM: is the goal specific enough?
    LLM-->>BE: 3 goal candidates if vague (F-002)
    U->>FE: choose goal + difficulty (F-003)
    FE->>BE: POST /api/maps (create map + start generation job)
    FE->>BE: GET /api/maps/:id/generation (SSE, reconnectable)
    BE->>DB: load the user's existing nodes
    BE->>LLM: generate map (streaming, JSON Schema, existing nodes to reuse)
    loop each completed node
        LLM-->>BE: tokens
        BE->>DB: save node / map_nodes / paths / sub_nodes / detour
        BE-->>FE: SSE node event (read from DB)
    end
    BE->>DB: mark map ready
    BE-->>FE: SSE done
    FE->>BE: GET /api/maps/:id
    BE-->>FE: main nodes + paths + compass
    U->>FE: pick a compass candidate, update progress
    FE->>BE: PATCH /api/maps/:mapId/nodes/:nodeId/progress
    BE-->>FE: updated compass
```
