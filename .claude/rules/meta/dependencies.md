---
paths:
  - "backend/Gemfile"
  - "backend/Gemfile.lock"
  - "frontend/package.json"
  - "cli/go.mod"
  - "docker-compose.yml"
---

# External Packages

Approved gems (see `backend/Gemfile`): `rails` (~> 7.1.0), `mysql2`, `google-genai`, `dotenv`, `faraday` (used directly to call the LLM, `docs/basic-design.md` section 7.2; for now it is only in the Gemfile.lock as a `google-genai` dependency). Ruby 4.0.5.

Also approved for Web login (F-019, `docs/basic-design.md` section 7.3), not in the Gemfile yet: `omniauth`, `omniauth-google-oauth2`, `omniauth-github`, `omniauth-rails_csrf_protection`, `rack-cors`.

Approved for the CLI (Go, `cli/`, `docs/basic-design.md` section 4.1): `github.com/spf13/cobra` (with its dependencies `spf13/pflag` and `inconshreveable/mousetrap`). HTTP and SSE use the standard library. The CLI binary depends only on the standard library and cobra.

Approved for development and tests only, to check the API against `api/openapi.yaml` (`docs/basic-design.md` section 8); none of them ships in production, and none is added yet. Check each one's maintenance and vulnerability record when adding it to its app: `committee` (gem, backend tests), `openapi-typescript` (npm, frontend type generation), `oapi-codegen` (Go tool, CLI type generation only: `-generate types`), Prism (a Compose service for tests, validating proxy).

Ask the user before adding any other gem, npm package or Go module.
