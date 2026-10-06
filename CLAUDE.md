# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Project Overview

Campass is a learning-path recommendation app. The user enters a goal, an LLM generates a syllabus as a dependency graph (JSON), and the app shows it as a 学習マップ (learning map) with a compass that points to the nodes the learner can study next ("トップダウン逆算型ボトムアップ学習"). There is no linear roadmap view (removed in ReqDef v1.2.0).

## Source of Truth

- `doc/ReqDef.md` — requirements. Feature IDs `F-001`…`F-013` (F-005 and F-008 are 廃止) are used across all docs.
- `doc/basic_design.md` — system layout, screens, DB overview (ER diagram only), external API integration.
- `doc/design_doc.md` — table definitions (source of truth, section 4.1.2), algorithms, REST/SSE API, alternatives considered, test plan, open issues (section 9).

**`README.md` is out of date about the tech stack** (it says Next.js / Node.js / PostgreSQL). The actual stack is **React (SPA) + Ruby on Rails (API) + MySQL**. Follow the design docs.

## External Packages

Approved gems (see `Gemfile`): `rails` (~> 7.1.0), `mysql2`, `google-genai`, `dotenv`. Ruby 4.0.5.

Ask the user before adding any other gem or npm package.

---

## Rules (Do NOT violate)

- LLM / Embedding API keys stay in the backend only. Never send them to the frontend, and never hardcode them.
- Do not follow the tech stack in `README.md`; use the design docs.
- Do not implement the 学習マップ (map view) or the cross-notebook-link UI before its open issues (`doc/design_doc.md` section 9) are settled with the user.

---

## Commands

Everything runs through Docker Compose: `web` (Ruby 4.0.5) and `db` (MySQL 8.0). Gems are kept in the `bundle_data` volume.

```bash
docker compose up -d --build      # start web + db
docker compose exec web bash      # shell in the app container (/app = repo root)
bundle install                    # inside the container
ruby gemini_comu.rb               # inside the container: manual Gemini API check
```

`.env` (gitignored) must define `GEMINI_API_KEY`, `MYSQL_ROOT_PASSWORD`, `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD`. Compose maps the MySQL values into the `web` container as `DB_HOST`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`; Rails `database.yml` should read those names.

### Tests

@.claude/rules/test/testing.md

---

## Architecture

### Overall architecture

@.claude/rules/code/architecture.md

### Frontend

@.claude/rules/code/frontend.md

### Backend

@.claude/rules/code/backend.md

---

## LLM Integration

@.claude/rules/code/llm-integration.md

---

## Error Handling

@.claude/rules/meta/error.md
