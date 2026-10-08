# Frontend Architecture

React SPA. Design from `docs/basic_design.md` sections 2.2 and 3, and `docs/design_doc.md` section 4.4. Not implemented yet; the directory layout and libraries (router, state management, graph rendering) are not chosen. Ask the user before adding any npm package.

## Layers

```mermaid
graph TD
    subgraph FE[Frontend: React SPA]
        UI["UI component layer<br/>S-01 map list / S-02 initial input / S-03 map screen"]
        State["State layer<br/>current map, nodes, compass"]
        API["API client layer<br/>REST requests + SSE receiver"]
    end
    BE[Backend: Rails API]

    UI -->|user actions| State
    State -->|render| UI
    State -->|calls| API
    API -->|REST| BE
    BE -.->|SSE node events| API
    API -->|append node| State
```

| Layer | Responsibility |
| :--- | :--- |
| UI components | Screens and user input. Never calls the backend directly. |
| State | App state shared across screens (current map, nodes, compass). |
| API client | All backend communication, including receiving the SSE stream for map generation. |

## Screens

Details: `docs/design_doc.md` section 4.4.

```mermaid
graph TD
    S01["S-01 Map list<br/>/maps"]
    S02["S-02 Initial input<br/>/maps/new"]
    S03["S-03 Map screen<br/>/maps/:mapId?node=:nodeId"]

    S01 -->|create map| S02
    S01 -->|open map| S03
    S02 -->|generation started| S03
    S03 -->|make a map from a detour| S02
    S03 -->|origin node / detour entrance / back to previous map| S03
    S03 -->|back| S01
```

## Rules

- **There is no linear roadmap view.** Do not build one, and do not sort nodes into a single order on the client.
- **Render streamed nodes one at a time.** Move to S-03 as soon as the last assessment answer is sent. Each SSE `node` event carries one complete node; add it to state and draw it immediately. Reused nodes arrive already filled in (F-009). Show the compass only after `done`.
- **Map screen**: first draw only main nodes, with titles and paths only (no `summary` until a node is selected). Center the initial view on the current position and its surroundings. Selecting a node opens the detail panel (`GET /api/maps/:mapId/nodes/:nodeId`) and keeps the selection in `?node=`.
- **Drill-down (F-007)**: fetch `GET /api/nodes/:id/sub_nodes` and expand the sub nodes as a graph inside that node. For an origin node, move to its map instead.
- **Marks**: shared nodes get a "common with other maps" mark; origin nodes a "has a map inside" mark. A detour without a map appears only in the detail panel; once a map is made from it, draw a dashed dead-end entrance from its main node. Detour entrances have no progress.
- **Navigation between maps**: browser back plus a "← back to previous map" link. No breadcrumb (shared nodes give a map several parents).
- **Compass**: mark the current position (none = start point) and point at every candidate. Use `compass` (`current_node_id`, `candidates` sorted by `importance_score`, `is_goal_reached`) from the backend as-is; never derive it on the client. Highlight the first candidate. Any node can be started, not only candidates. After a progress update, use the `compass` returned by `PATCH /api/maps/:mapId/nodes/:nodeId/progress`; if it returns `origin_completion_suggestion`, ask whether to complete the origin node.
- **First visit**: on the user's first S-03 only, show three skippable hints (current position, compass, select a node).
- **Map deletion**: show `GET /api/maps/:id/deletion_preview` first and warn that nodes started in this map stay in progress in the other maps.
- The frontend never holds or receives the LLM API key.
