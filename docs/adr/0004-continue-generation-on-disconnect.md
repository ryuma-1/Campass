# Map generation continues when the client disconnects

Generating a map takes tens of seconds, and the learner is moved to the map screen as soon as generation starts so they can read nodes while they appear. Reloading or leaving that screen, or pressing Ctrl+C in the CLI, therefore happens often, and the backend cannot tell these apart: it only sees the SSE connection close. We run generation as a background job detached from the request (ActiveJob with the `:async` adapter), so it runs to the end whatever the client does. The job only saves nodes to the database, one node per transaction; the SSE endpoint (`GET /api/maps/:id/generation`) reads saved nodes from the database, sends all of them on every connection, then sends new ones until the map is `ready`, `failed` or deleted. Creating a map and starting its generation are one request (`POST /api/maps`), so a map has no state before generation.

## Considered Options

- Stop generation when the connection closes (the Rails `ActionController::Live` default): rejected because a reload or a stray tab close would break the map.
- Let the job push nodes to the SSE connection directly: rejected because nodes saved and nodes sent could then differ, which is the rollback problem the streaming design left open.
- Resume with `Last-Event-ID`: rejected because a reload loses the last ID anyway, so the client would ask for everything again while the server must manage event IDs.
- Poll `GET /api/maps/:id` after reconnecting: rejected because nodes would appear in batches instead of one by one.
- Run the job with Solid Queue so it survives a restart: rejected for now because it adds a gem, a worker process and queue tables, and a rerun cannot resume the LLM stream, so it would regenerate nodes that clients have already been sent.
- An explicit "cancel generation" that keeps the map: rejected because a half-built map has no use; deleting the map, which is allowed while generating, covers it.

## Consequences

The `:async` job dies with its process, and it cannot report that itself. A map stays `generating` only while the job keeps saving nodes: each save updates `maps.generation_heartbeat_at`, and a `generating` map without a save for a set time (5 minutes to start with) is marked `failed` with `timed_out` when the SSE loop or a map-reading API looks at it. Errors inside the job are saved as `failed` with an error code right away. A failed map is never resumed; it keeps its saved nodes for reading and is deleted and made again, which keeps the learner's progress through node reuse (ADR 0003). Because the job and map deletion both lock the `maps` row before writing, a node is either saved completely before the deletion or not at all, and a job that finds its map gone stops quietly.
