# Nodes belong to the learner and are shared across maps

Design doc v0.3.0 kept each map's nodes separate and only linked similar nodes across maps after the learner accepted an embedding-based proposal. We now make a node belong to the learner: when a new map is generated, the LLM is given the learner's existing nodes and reuses one instead of creating a duplicate, so the node appears in several maps with a single progress. What a node teaches (title, summary, its sub nodes, progress) is shared; where it sits in a given goal (the paths between main nodes, whether it is a main node there, its importance) belongs to each map, so adding a map never rewires another map's graph. Reuse is automatic, without an approval step, because the LLM decides it with the goal and the existing nodes in context, unlike the title-similarity check that made approval necessary.

## Considered Options

- Separate nodes linked by accepted cross-map links (the earlier design): rejected because the learner would study and track the same content twice, and the link alone did not carry progress.
- Ask the learner to approve each reuse during generation: rejected because it interrupts watching the map being built.
- Find duplicates after generation with embeddings and remove them: rejected because removing a node cuts the paths that pointed to it, and the node may already have been streamed to the client.

## Consequences

A map no longer owns its nodes; map-specific attributes move to a per-map placement of each node. Because content is shared, a later map can deepen a reused node by adding sub nodes inside it, and those sub nodes then also appear when drilling down in earlier maps. Unsharing a node is not supported for now.
