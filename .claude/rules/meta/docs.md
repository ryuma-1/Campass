---
paths:
  - "docs/req-def.md"
  - "docs/basic-design.md"
  - "docs/design-doc.md"
  - "docs/adr/**"
  - "docs/plans/**"
  - "api/**"
  - "GLOSSARY.md"
---

# Documents

- `GLOSSARY.md` — domain terms; use them in code, docs and UI text. `docs/adr/` records why the model is shaped this way.
- `docs/req-def.md` — requirements only, as users and operators see them (no tech, tables, APIs or algorithms). Feature IDs `F-001`…`F-020` (F-004, F-005 and F-008 are 廃止) are used across all docs.
- `docs/basic-design.md` — the source of truth for every concrete spec: system layout and tech stack (section 2), screens (3), CLI (4), table definitions (5.4), processing rules (6), REST/SSE API behaviour (7.1), LLM API (7.2), Web and CLI auth (7.3, 7.4), test design (8). No reasons; it links to the design doc instead.
- `docs/design-doc.md` — why only: trade-offs, alternatives considered, concerns (section 5), open issues (section 6). No spec; it links to basic-design.
- `api/openapi.yaml` (OpenAPI 3.0.3; `committee` cannot read 3.1) — the API's shape: paths, parameters, request and response JSON, status codes, error `code` values, SSE event `data`. No `examples`; the schemas are the only source.

**When you change the API's shape, fix `api/openapi.yaml` and `docs/basic-design.md` section 7.1 in the same change.**

Each doc states only its own role: put each statement in the one doc its role allows, and link to it from the others.
