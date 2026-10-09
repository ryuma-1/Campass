# A main node may also appear inside another main node of the same map

Since sub nodes are shared (ADR 0003), a node can be a main node of a map and, at the same time, a sub node (at any depth) of another main node of that map. We allow this instead of forbidding it, and mark such a main node on the map screen ("also inside 'A'") so that a learner who completes it is not surprised to see it completed inside A too. When the learner adds a main node by hand, the suggested existing nodes show where they already appear in the map, so the learner can choose to draw a path to the existing node instead.

## Considered Options

- Forbid it in every map: rejected because a sub node added to a shared node can create the overlap in another map the learner is not looking at. Rejecting that edit restricts what the learner can build because of another map's structure, and fixing the other map by removing its main node silently deletes its paths and moves its current position. LLM generation would also need one more validation and more retries.
- Forbid it only when building the map itself (adding main nodes, generation): rejected because the rule would still not hold in every map, so it would only be a partial guarantee that code could not rely on.
- Hide the inner copy in that map: rejected because sub nodes are meant to be the same in every map.

## Consequences

Within one map, a node is still placed at most once as a main node (`map_nodes` is unique per map and node). Progress is one per node, so the main node and its copy inside another main node always show the same progress. A path from a node to its own sub node stays a prompt-level warning in generation, not a validation error.
