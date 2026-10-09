# Current position is derived from each map's progress history

The current position was stored as one value per map (`maps.current_node_id`), set whenever a main node was started or completed in that map. Once learners can remove main nodes from a map (F-018), removing the node at the current position must move the position back to where it was before, and a single stored value cannot say where that was. We now record every start, completion and reset made from a map as a progress event of that map, and derive the current position as the node of the latest start or completion event whose node is still placed in the map and has not been reset since. Events are kept when their node is removed, so the history can be shown to the learner later.

## Considered Options

- Keep `maps.current_node_id` and fall back to a node with a path into the removed one: rejected because it is a guess, and with several such nodes there is no natural choice.
- Store "last started or completed in this map" as a time on each placement (`map_nodes`) and take the latest: gives the same current position, but each time overwrites the earlier one, so the history is lost and cannot be shown later.
- Reset the current position to the start point: rejected because the learner loses their place for a change that has nothing to do with progress.

## Consequences

Events point to the placement (`map_nodes` row) they were made through, not only to the node, so a node removed and placed again does not bring back its old events. Progress is still shared across maps, but events are recorded only in the map the learner acted from, so the current position of other maps does not move, as before. Resetting a node to not started also moves the current position back, which the stored value did not do.
