# Detours are proposals for new maps, not nodes in the map

Optional, loosely related themes (formerly サブクエスト, `route_type = sub` nodes drawn as side paths) are now 寄り道: proposals attached to a main node that, if the learner wants, start a new map with the detour's theme as its initial interest; any content the two maps have in common is shared through reused nodes, with no special connection. A theme the learner will not study in this map does not fit the definition of a node, and keeping it as a node meant excluding it from progress, the compass and goal-reached checks everywhere. Removing it lets every node in a map be part of reaching the goal, and drops `route_type` and `related_main_node_id` from nodes.

## Considered Options

- Keep detours as nodes drawn as side paths but excluded from progress and the compass: rejected because every rule over nodes would need a special case.
