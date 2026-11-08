# The compass shows only after the node at the current position is completed

The compass used to be on the map screen at all times, pointing at every compass candidate even before the learner had started anything. With a starting node (ADR 0008), the learner is already at a node when the map is made, so there is nothing to choose yet. The compass now shows only while the node at the current position is completed: it is the guide for the moment the learner finishes a node and moves on. While that node is not started or in progress, or when there is no current position, it is hidden. This is derived from the progress history (ADR 0005), so it looks the same after a reload and in the CLI.

The compass still points at every candidate, but orders them: first unfinished nodes that lead into a completed node of the map (prerequisites skipped by beginning in the middle), then the nodes right after the node just completed, then the rest, by importance within each group. Skipped prerequisites come first so that what the learner jumped over is filled in before going further.

## Considered Options

- Keep the compass always visible and, while the starting node is not started, point only at it: rejected because the learner has not finished anything yet, so the compass would only repeat the current position.
- After completing a node, point only at the nodes right after it, and fall back to all candidates at a dead end: rejected because skipped prerequisites would drop out of the guide, while the learner wants them first. The compass guides and does not restrict, so ordering is enough and no candidate is removed.

## Consequences

A map whose starting node is already completed shows the compass right after it is made. The API returns an empty candidate list whenever the compass is hidden, and clients show the compass only when the list is not empty.
