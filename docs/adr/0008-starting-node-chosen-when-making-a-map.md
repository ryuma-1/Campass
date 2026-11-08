# Every map starts at a starting node chosen when it is made

Learners do not always want to begin at the bottom of the prerequisites: someone who wants to understand Ruby may want to begin with classes, and learn variables and functions only as far as classes need them. When a map is made, the learner now also picks a starting node, the thing they want to learn first. The LLM suggests three candidates and recommends one, taking into account what the learner has completed in other maps; if the learner picks nothing, the recommendation is used, so every map is made with a starting node. Generation then lays out the nodes from the starting node to the goal, plus the prerequisites the starting node directly needs. The map stores the starting node as a placement (`map_nodes` row), and until the learner starts or completes a node in that map, the starting node is the current position. Its progress is not changed.

## Considered Options

- Two kinds of map, one with only a goal and one with a goal and a starting node: rejected because both have the same nodes, paths and compass; only the prompt and one input differ.
- Make the starting node optional when making a map: rejected because a learner always begins somewhere, and the LLM can always recommend a place, so leaving it out would only add a second way to begin.
- Mark each node as "prerequisite of the starting node" or "towards the goal": rejected because the position in the graph already tells it, and a node shared by several maps can be a prerequisite in one map and the starting node in another.
- Set the starting node to "in progress" when the map is made: rejected because progress is shared across maps and is always the learner's decision (design doc 4.4).
- Keep a starting node for the whole life of a map (refuse to remove it, or move it elsewhere): rejected because it only has to exist at the beginning. The learner may remove it from the map later, and the map then simply has none.

## Consequences

The current position from ADR 0005 falls back to the starting node when the map has no events, and there is no current position only when the starting node was removed before anything was started or completed. When the learner does not pick a starting node through the API, the generation job asks for the recommendation before generating, so the rule lives in the backend only. A missing `start_ref` in the LLM output is known only once the whole output has arrived, so it joins the open question on regenerating after nodes were saved.
