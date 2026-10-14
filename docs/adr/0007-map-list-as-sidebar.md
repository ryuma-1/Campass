# The map list is a sidebar, polled only while it is open

Learners switch between maps often (origin nodes, detours and shared nodes link them), and going back to a separate map list screen (S-01) for every switch broke their focus on the map. We removed S-01 and show the map list as a sidebar on S-02 and S-03; `/`, `/maps` and a login without `return_to` redirect to the map with the latest `updated_at`, or to S-02 when there is none. On wide screens the sidebar sits beside the map and shrinks it instead of overlaying it, because an overlay would hide part of the initial view (the current position and its surroundings) and of "fit all", and hide nodes from interaction. The list is fetched every 30 seconds only while the sidebar is open and the tab is visible, so spinners, failure icons and deletions elsewhere show up quickly; a closed sidebar shows nothing, so it is not polled.

## Considered Options

- Keep S-01 as a screen: rejected because every switch between maps left the map, and the list held information (notes, delete buttons) the learner rarely needs while switching. Notes moved under the map title on S-03 and deletion to the S-03 menu.
- Overlay the sidebar on wide screens too: rejected for the reasons above.
- Never poll (the previous rule, #5): rejected because the open sidebar would show a stale status for maps generating in another tab or the CLI.
- Push updates (WebSocket / SSE for the list): rejected as a new channel for a list that only needs to be roughly fresh.

## Consequences

`maps.updated_at` now decides the list order and where the learner lands, so it is touched on every side effect made through the map (basic_design 5.5), not only when the `maps` row changes. Keeping the content of an open S-03 in sync with changes made elsewhere is a separate open issue (#24).

Update (design_doc v0.18.0, #24): an open S-03 is refetched only when the learner comes back to it (`visibilitychange` to `visible` or `window` `focus`, at most once per 2 seconds), never polled or pushed, because shared nodes (ADR 0003) would make detecting changes to one map heavy for a single-user app. The sidebar's immediate list fetch uses the same trigger. Details are in design_doc 4.4.
