# Unify "notebook" and "learning map" as "map"

A learner's per-goal workspace was called a ノートブック, and the network view of its contents a 学習マップ, but the two are always one-to-one: a notebook holds exactly one goal and one graph, and nothing else. We call the workspace, its contents and its screen a マップ, because the product's concept is "fill in a map, guided by a compass", and the compass and current position already force users to learn the map metaphor. We dropped ノートブック even though it may be more familiar as a container name, because two words for one thing made users assume they were different things.

## Considered Options

- Keep ノートブック as the container and 学習マップ as its view (the earlier design): rejected because users would read them as different things.
- Use マップ in code and docs but ノートブック in UI text: rejected because the code and the screens would use different words.

## Consequences

Table names (`notebooks`, `cross_notebook_links`), API paths (`/api/notebooks/...`), ReqDef F-012 and the CLI commands are renamed to match before implementation starts.
