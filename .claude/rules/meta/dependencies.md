---
paths:
  - "backend/Gemfile"
  - "backend/Gemfile.lock"
  - "frontend/package.json"
  - "cli/go.mod"
  - "docker-compose.yml"
---

# Approved Packages

Every gem in `backend/Gemfile` is approved. Also approved, not added yet:

- Backend: `faraday`, to call the LLM directly (`docs/basic-design.md` section 7.2); it is only in `Gemfile.lock` now, as a `google-genai` dependency, so add it to the Gemfile when the code uses it. For Web login (F-019, section 7.3): `omniauth`, `omniauth-google-oauth2`, `omniauth-github`, `omniauth-rails_csrf_protection`, `rack-cors`.
- CLI (Go, `cli/`, section 4.1): `github.com/spf13/cobra` (with its dependencies `spf13/pflag` and `inconshreveable/mousetrap`). HTTP and SSE use the standard library; the binary depends only on the standard library and cobra.
- Development and tests only, never shipped to production, to check the API against `api/openapi.yaml` (section 8): `committee` (gem, backend tests), `openapi-typescript` (npm, frontend type generation), `oapi-codegen` (Go tool, CLI type generation, `-generate types` only), Prism (a Compose service for tests, validating proxy). When adding one, check its maintenance and vulnerability record.
