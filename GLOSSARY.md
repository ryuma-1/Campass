# Campass

Campass helps self-learners reach a goal by working backward from it: an LLM lays out the prerequisite knowledge as a graph, and the learner moves through it with a map and a compass.

## Language

### Map contents

**ノード (Node)**:
One learning item. A node belongs to the learner and can appear in more than one map.
_Avoid_: 地点, ステップ, step

**道 (Path)**:
A directed connection from one node to another that shows a recommended learning order: when a path runs from A to B, learning A before B is recommended. It guides; it does not lock B.
_Avoid_: 前提, prerequisite, 依存関係, dependency, エッジ, edge, 順路, 必須の前提, 補足の前提, supplementary

**メインノード (Main node)**:
A node at the top level of a given map, shown on the map screen from the start. The same node can be a main node in one map and a sub node in another, and even inside another main node of the same map.
_Avoid_: メインルート, main route, 大枠の地点

**サブノード (Sub node)**:
A node that is a piece of what another node covers ("B is a sub node of A"), at any depth. It is the same in every map and is seen by drilling down. The nodes of a map made from an origin node are sub nodes of that node. Completing every sub node is not required to complete the node.
_Avoid_: 部分, part, 全体, whole, 要素, element, 構成要素, component, 子ノード, child node, 中身, サブクエスト

**寄り道 (Detour)**:
A theme branching from a specific main node that is only loosely related to the map's goal and need not be learned; offered so the learner can start a new map for it if they want. It is not a node and has no progress.
_Avoid_: サブクエスト, sub quest, サブノートブック, サブマップ, 派生テーマ, わき道

**マップ (Map)**:
A learner's independent workspace for one goal: the nodes leading to that goal and the paths between them, shown as a network. Learned nodes are filled in, and filling in every main node means reaching the goal. "Map" is a metaphor; nodes have no coordinates.
_Avoid_: ノートブック, notebook, ノート, note, 章, chapter, 学習マップ, シラバス, syllabus, curriculum, roadmap

### Navigation

**現在地 (Current position)**:
The node the learner is at in a given map: the node most recently started or completed in that map, otherwise the start point (no node). Each map has its own current position.

**コンパス (Compass)**:
The element on the map screen that points from the current position to every compass candidate. It guides; the learner may start any node.

**コンパス候補 (Compass candidate)**:
An unfinished main node of a map that the learner can study now: every node with a path into it is completed or a known node. A known node is not a candidate itself.
_Avoid_: 進める方角, next step

**既知ノード (Known node)**:
A node in a map that the learner has already started or completed in another map, so this map treats it as understood to some degree.
_Avoid_: 既習ノード, learned node, 再利用ノード

**ドリルダウン (Drill-down)**:
Expanding a main node to show its sub nodes.

### Across maps

**元ノード (Origin node)**:
A node that a map was made from because the node was too large to learn as one node. It stays a normal node in every map it appears in, and has at most one such map. Reaching that map's goal only suggests completing the origin node; the learner decides.
_Avoid_: 親ノード, parent node, マップ化, サブマップ, 展開

**寄り道の出発点 (Detour start)**:
The main node a detour map was made from. The map is reached from it on the map screen, but reaching the detour map's goal does not change the start's progress.
_Avoid_: 元ノード, origin node

**マップ間ノード (Shared node)**:
A node that appears in two or more maps of the same learner. It is one node, so its progress is the same in every map it appears in.
_Avoid_: マップ間リンク, cross-map link, クロスノートブックリンク, cross-notebook link, 重複ノード
