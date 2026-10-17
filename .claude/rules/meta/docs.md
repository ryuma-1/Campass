---
paths:
  - "docs/req-def.md"
  - "docs/basic-design.md"
  - "docs/design-doc.md"
  - "docs/adr/**"
  - "api/**"
  - "GLOSSARY.md"
---

# Documents

Each doc states only its own role: put each statement in the one doc its role allows, and link to it from the others.

- `docs/req-def.md` — requirements only, as users and operators see them (no tech, data formats, tables, APIs, algorithms or UI parts). Its feature IDs (`F-xxx`) are used across all docs.
- `docs/basic-design.md` — the source of truth for every concrete spec: system layout and tech stack (section 2), screens (3), CLI (4), table definitions (5.4), processing rules (6), REST/SSE API behaviour (7.1), LLM API (7.2), Web and CLI auth (7.3, 7.4), test design (8). No reasons; link 「（理由：Design Doc x.y）」 instead.
- `docs/design-doc.md` — why only: decisions with their trade-offs and alternatives (section 4), concerns (5), open issues (6). No spec; it links to basic-design.
- `docs/adr/` — one decision per file about why the domain model is shaped this way.
- `GLOSSARY.md` — domain terms and the synonyms to avoid; docs and UI text use these terms.
- `api/openapi.yaml` (OpenAPI 3.0.3; `committee` cannot read 3.1) — the API's shape: paths, parameters, request and response JSON, status codes, error `code` values, SSE event `data`. No `examples`; the schemas are the only source.

**When you change the API's shape, fix `api/openapi.yaml` and `docs/basic-design.md` section 7.1 in the same change.**
