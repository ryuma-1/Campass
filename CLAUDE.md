# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Project Overview

Campass is a learning-path recommendation app. The user enters a goal, an LLM generates a マップ (a graph of nodes and 道), and the app shows it with a compass that points to the nodes the learner can study next ("トップダウン逆算型ボトムアップ学習"). Nodes belong to the user and are shared across maps. There is no linear roadmap view (removed in ReqDef v1.2.0).

## Rules (Do NOT violate)

- LLM API keys and the Google / GitHub OAuth secrets stay in the backend only, and are never hardcoded. The service's LLM key and the OAuth secrets never reach the frontend. A learner's own LLM key (F-020) touches the frontend only once: the learner types it on S-05 and it is sent over HTTPS; the backend stores it encrypted and never returns it in any response or writes it to logs.
- Before implementing anything listed in `docs/design-doc.md` section 6 (open issues), settle it with the user.
- Edit `docs/`, `api/openapi.yaml` and `GLOSSARY.md` only when the user asks.
- Ask the user before adding any gem, npm package or Go module not approved in `.claude/rules/meta/dependencies.md`.

---

## Commands

The repo is split into `backend/` (Rails API), `frontend/` (React SPA, empty for now) and `cli/` (Go CLI, empty for now). Everything runs through Docker Compose (`docker-compose.yml`), one service per directory, each mounting its directory at `/app`.

```bash
docker compose up -d --build                     # start backend + db
docker compose exec backend bundle install       # install gems
docker compose exec backend ruby gemini_comu.rb  # manual Gemini API check
docker compose run --rm cli go test ./...        # run the CLI tests
```

`.env` (gitignored, at the repo root) must define `GEMINI_API_KEY`, `LLM_PROVIDER`, `LLM_MODEL` (`gemini` / `gemini-3.1-flash-lite` for now; the backend also falls back to these when unset), `MYSQL_ROOT_PASSWORD`, `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET`, `FRONTEND_ORIGIN` (`http://localhost:5173` in development), `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`, `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` and `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT`.

---

## Agent skills

### Issue tracker

Issues are tracked in GitHub Issues for `ryuma-1/Campass`, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five default triage labels are used as-is (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
