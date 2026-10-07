# Design Doc：Campass

* **ステータス**: Draft
* **著者**: 池田 琉俊
* **作成日**: 2026/07/01
* **要件定義書**: `ReqDef.md`（v1.3.0 / 2026/10/06）

---

## 1. 目的（Goal）

本システムの目的は，独学者が「次に何を学べばいいかわからない」「基礎学習の先が見えず挫折する」という課題を解消することである．LLM がユーザーの学習ゴールから前提知識の依存関係をグラフ構造として計算し，そのグラフを (a) ノートブックの依存関係そのものを地図のように俯瞰できる「学習マップ」として動的に提示し，(b) 学習マップ上では「コンパス」が学習者の現在地から次に学べるノードを指し示す状態を実現する．「地図を広げ，コンパスで進む方向を確かめながら学ぶ」というのが本アプリ（Campass）のコンセプトである．加えて，(c) 他のノートブックに強く関連するノードが見つかった場合は，それをユーザーに提案し，ノートブックを横断したつながりを本人の意思で発見・接続できる状態も目指す．

技術的な観点では，(1) LLM によるシラバス（グラフ構造）の構造化データ生成，(2) 単一ノートブックのグラフ構造を学習マップとして提示しつつ，進捗から現在地と次に学べるノードを導出するロジック，(3) 他ノートブックとの関連ノードを検出し，ユーザーへの提案・承認を経て接続として記録するデータモデル，の3点を無理なく成立させる設計を確立することが本 Design Doc のスコープである．

### 1.1 Non Goals

* **独自LLMの学習・ファインチューニング**: 既存の外部LLM API（Claude / GPT / Gemini 等）を利用する前提とし，モデル自体の開発は行わない（ReqDef 3.2）．
* **教材コンテンツそのものの制作**: 各学習ステップの本文教材を自社で執筆・作成することは行わない．外部記事へのリンク提示とAIによる概要生成，課題提示に留める（ReqDef 3.2）．
* **詳細画面仕様・Pixel Perfect なUI定義**: 画面レイアウトの厳密な仕様はFigma等の別ドキュメントに委ね，本Docでは認知負荷軽減の設計方針までを扱う．
* **本Docでの要件の再定義**: 機能要件・非機能要件の是非そのものは ReqDef.md で確定済みという前提に立ち，本Docでは「その要件をどう実現するか」のみを議論する．

## 2. 背景（Background）

独学者は「最終的に何ができるようになりたいか（ゴール）」は漠然と持っていても，そこに至るまでの前提知識の依存関係を自力で把握することが難しく，基礎学習の途中で「これが何に繋がるのか分からない」まま離脱してしまうケースが多い（ReqDef 2.1）．また，表面的なツールの使い方（ハウツー）の習得に偏り，背後にある原理原則の理解に到達しないまま学習が止まってしまう問題もある．

これに対し，本アプリは「トップダウン逆算型ボトムアップ学習」，すなわちゴールから逆算して必要な前提知識を洗い出し，基礎から順に積み上げていく学習プロセスを LLM に計算させることで解決を図る．一方で，計算された依存関係は本質的にはグラフ（ネットワーク）構造になりやすく，そのまま提示すると学習者の認知負荷が高く「今何をすべきか」が分かりにくい．そのため，グラフ構造をそのまま学習マップとして見せつつ，ドリルダウン（F-007）で情報量を絞り，コンパス（F-013）で「次に進める場所」を示すことで認知負荷を抑えることが本システムの中核的な設計上の論点になる．なお，当初はグラフを一本道（リニア）に変換して見せる設計（旧 F-005, F-008）であったが，v0.5.0 で廃止した．

さらに，独学者は単一のゴールだけでなく，「AIも学びたいがデザインにも興味がある」のように複数の学習テーマを並行して抱えるケースが多い．この場合，テーマごとに学習順序だけを提示すると，学習者は依存関係全体の「構造」自体を意識する機会が乏しく，また，他のノートブックで既に学んだ内容（例：統計学の基礎）が今のノートブックにも関連していることに気づきにくい．ReqDef 5.2 では，この課題への対応として前提知識の関連性を可視化する「学習マップ」への拡張性が言及されており，本バージョンではこれを拡張性の考慮に留めず，実装スコープに含める（1章参照）．具体的には，(a) 学習マップは同一ノートブック内のグラフ構造をネットワーク図として可視化するものとし，(b) 他ノートブックとの関連は自動統合ではなく，関連の強いノードが見つかった際にユーザーへ提案し，承認した場合のみノード間リンクとして記録する，という設計方針とする．

用語定義:

| 用語 | 定義 |
| :--- | :--- |
| シラバス | LLMが生成する，ゴールに至るまでの学習項目とその依存関係を表す構造化データ（JSON）． |
| メインルート | ゴール到達に必須な学習ステップの集合（`route_type = main`）． |
| サブクエスト | メインルートの理解を補強する任意（寄り道）の学習項目． |
| ノートブック | ユーザーが学習テーマごとに保持する独立した作業スペース（ReqDef F-012）． |
| ドリルダウン | 大枠のステップをクリックすることで内部の詳細な前提知識を展開する操作（ReqDef F-007）． |
| 学習マップ | 同一ノートブック内のシラバスグラフ（ノード・エッジ）をそのまま可視化した俯瞰図．「地図」はコンセプト上の比喩であり，ノードは地理的な座標を持たない． |
| 現在地 | 学習マップ上で学習者が今いる地点．学習中（`in_progress`）のノード，なければ直近に完了したノードを指す．どちらもなければ「スタート地点」（ノードなし）とする（4.2.8）． |
| 進める方角（コンパス候補） | 必須の前提ノードがすべて完了している未完了のメインルートノード．複数存在し得る（4.2.8）． |
| コンパス | 学習マップ上で，現在地から「進める方角」をすべて指し示すUI要素（ReqDef F-013）．`importance_score` の高い候補を強調し，どれに進むかはユーザーが選ぶ． |
| クロスノートブックリンク | 異なるノートブックに属するノード同士が強く関連すると判定された際に，ユーザーへ提案され，承認された場合に記録されるノード間の接続．ノード自体は統合されず，別個体のまま繋がりのみが追加される． |

## 3. 概要（Overview）

本システムは，React 製フロントエンド，Ruby on Rails 製バックエンド，MySQL データベース，および外部LLM API（Claude 等）から構成される Web アプリケーションである（ReqDef 6章）．ユーザーの入力はバックエンドを経由してLLM APIへ送信され，生成されたシラバスJSONはストリーミング形式で逐次フロントエンドへ返却・描画される．これにより，生成に数十秒を要する処理でもユーザーは最初の一歩をすぐに読み始めることができる（ReqDef 5.2）．

システムが扱う中心的なデータは「グラフ構造を持つシラバス」であり，これを (a) 依存関係を正しく表現できるデータ構造として永続化しつつ，(b) 学習マップ（ネットワークのまま）として提示し，(c) 進捗から現在地と進める方角（コンパス）を導出するロジックが本システムの技術的な核となる．これに加えて，(d) 他ノートブックの既存ノードと強く関連する新規ノードが生成された際に，その関連をユーザーへ提案し，承認された場合は「クロスノートブックリンク」として記録する仕組みを持つ．(d) はノードの統合を伴わず，別個体のノード同士に接続を追加するだけであるため，(b)(c) のロジック自体には影響しない．

### 3.1 ハイレベルアーキテクチャ

```
┌────────────────┐        ┌──────────────────────┐        ┌────────────────────┐
│   Frontend      │  HTTP  │   Backend             │  HTTPS │  外部LLM API         │
│   (React)       │◄──────►│   (Ruby on Rails)     │◄──────►│  (Claude / GPT等)    │
│                 │  SSE   │                        │  ストリーミング       │  ※オプトアウト設定必須 │
│ ・入力フォーム    │        │ ・シラバス生成オーケストレーション│        └────────────────────┘
│ ・学習マップUI    │        │ ・プロンプトテンプレート管理  │
│ ・ドリルダウン表示 │        │ ・ノートブック/進捗の永続化  │
└────────────────┘        │ ・APIキーの秘匿管理        │
                            └──────────┬─────────────┘
                                       │
                                       ▼
                            ┌──────────────────────┐
                            │   MySQL                │
                            │ ・User / Notebook       │
                            │ ・Syllabus (Node/Edge)  │
                            │ ・Progress / Assessment │
                            └──────────────────────┘
```

* フロントエンド（React）とバックエンド（Rails）は REST API + ストリーミング（Server-Sent Events）で通信する（4.3.1）．
* バックエンドは外部LLM APIキーを一元管理し，フロントエンドへは絶対に露出させない（ReqDef 5.3）．
* CLI（Go，ReqDef F-014）はフロントエンドと同列のクライアントとして同じ REST API + SSE を利用する．業務ロジックと外部APIキーは持たない（4.5）．
* MySQL はグラフ構造（ノード・エッジ）を表現可能なリレーショナル設計とし，学習マップ（単一ノートブック内のネットワーク表示）およびクロスノートブックリンク（ReqDef 5.2 の拡張性言及に対応）を見据える．

### 3.2 主要ユースケースフロー

ReqDef 4.2 のタイムライン形式の進行制御に対応する，代表的な一連の処理フローを示す．

1. ユーザーが学びたいことを自由入力する（F-001）．
2. バックエンドがLLMに「入力が具体的なゴールとして十分か」を判定させ，曖昧であれば3件のゴール候補を生成する（F-002）．ユーザーは候補から選択，または自由入力のまま次へ進む．
3. ユーザーが学習の深さ（ライト／スタンダード／ディープ）を選択する（F-003）．この選択値はLLMへのプロンプト制約（`max_depth` 等）としてそのまま渡される．
4. 決定したゴールに基づき，3〜5問の前提知識アセスメントを実施する（F-004）．回答結果は「既習スキップ対象ノード」としてシラバス生成プロンプトに反映される．
5. バックエンドがLLMへシラバス生成をリクエストし，ストリーミングでシラバスJSON（グラフ構造）を受信しながら，逐次DBへ永続化する（F-011）．
6. 受信したノードを，フロントエンドが学習マップ上に順次描画する（F-011）．
7. ユーザーは学習マップ上でコンパスが示す「進める方角」から次に学ぶノードを選び（F-013，4.2.8），各地点をドリルダウンして前提知識を展開したり（F-007），マイルストーンで成果物提示を行ったりしながら学習を進める（F-009, F-010）．進捗を更新すると，現在地と進める方角が再計算される．
8. シラバス生成中（ステップ5）に新規ノードが確定するたび，バックエンドは同一ユーザーの他ノートブックの既存ノードとの関連度をEmbedding類似度で計算する．強い関連が見つかった場合，「他のノートブック『◯◯』の『△△』と関連がありそうです」という提案をユーザーに提示する．
9. ユーザーが提案を承認すると，2つのノードの間にクロスノートブックリンクが記録される．学習マップ上では，このリンクを通じて他ノートブックのノードへの参照が示される（ノード自体は統合されない）．承認しない場合はそのまま提案を無視・却下でき，データには反映されない．

> **補足**: クロスノートブックリンクの提案（ステップ8〜9）は生成フローの中で発生する非同期的な追加ステップであり，ユーザーが応答しなくても学習マップの表示自体はブロックされない．

## 4. 詳細設計（Detailed Design）

### 4.1 データ構造設計

シラバスは本質的にグラフ（有向非巡回グラフ）であり，学習マップはこれをそのまま提示する．そのため，DB上は **ノード・エッジ方式** のグラフ構造として保持し，(a) 学習マップは同一ノートブック内の `syllabus_nodes` / `syllabus_edges` をそのまま描画する．並び順のような派生データは保持せず，現在地とコンパスは進捗（`progress_statuses`）とエッジから都度導出する（4.2.8）．一方，(b) 他ノートブックのノードとの関連は，ノードを統合せず「提案→承認」を経て記録される接続として `cross_notebook_links` という別テーブルで管理する．なお，関連度の判定アルゴリズム自体は9章のオープンな論点として引き続き検証対象である．

#### 4.1.1 ER図（論理構成）

```
users ──1:N── notebooks ──1:N── syllabus_nodes ──1:N── syllabus_edges (from_node_id)
                    │                   │  ▲                    │
                    │                   │  │ self (parent)      │ (to_node_id も syllabus_nodes を参照)
                    │                   │  └────────────────────┘
                    │                   ├──1:1── progress_statuses
                    │                   ├──1:N── assessment_answers（target_node_id 経由，NULLABLE）
                    │                   └──N:N── syllabus_nodes（他ノートブック，cross_notebook_links 経由）
                    └──1:N── assessment_questions ──1:1── assessment_answers
```

* `syllabus_edges` は `syllabus_nodes` に対して `from_node_id` / `to_node_id` の2本の外部キーを持つ自己参照的な多対多の中間テーブルであり，DAG（有向非巡回グラフ）を表現する．**同一ノートブック内のノード間のみ**を結び，学習マップはこのグラフをそのまま描画する．
* `syllabus_nodes.parent_node_id` は同テーブルへの自己参照であり，ドリルダウン（F-007）の親子階層を表す．これは「前提関係（依存）」を表す `syllabus_edges` とは別軸の関係である点に注意する（親子＝階層の入れ子，エッジ＝学習順序の依存）．
* `cross_notebook_links` は `syllabus_edges` とは異なり，**異なるノートブックに属するノード間**のみを結ぶテーブルであり，ユーザーの提案承認を経て初めてレコードが作成される（4.2.7）．
* アセスメント回答が既習判定に紐づく場合は，`assessment_answers.target_node_id` で対象ノードを参照する．

#### 4.1.2 テーブル定義

本節のテーブル定義を正とする（基本設計書 4章は概要のみを示し，本節を参照する）．

**`users`**

| カラム名 | 型 | 制約 | 説明 |
| :--- | :--- | :--- | :--- |
| `id` | BIGINT UNSIGNED | PK, AUTO_INCREMENT | |
| `name` | VARCHAR(255) | NOT NULL | ユーザー名 |
| `email` | VARCHAR(255) | NOT NULL, UNIQUE | メールアドレス |
| `password_digest` | VARCHAR(255) | NOT NULL | 認証用パスワードハッシュ |
| `created_at` / `updated_at` | DATETIME | NOT NULL | |

**`api_tokens`**（CLI 用の認証トークン，4.5.4）

| カラム名 | 型 | 制約 | 説明 |
| :--- | :--- | :--- | :--- |
| `id` | BIGINT UNSIGNED | PK, AUTO_INCREMENT | |
| `user_id` | BIGINT UNSIGNED | FK → `users.id`, NOT NULL, INDEX | |
| `token_digest` | CHAR(64) | NOT NULL, UNIQUE | トークンの SHA-256 ハッシュ（16進）．平文は発行時のレスポンスでのみ返し，DBには保存しない |
| `name` | VARCHAR(255) | NULLABLE | 発行元の識別名（例：ホスト名）．ユーザーが自分のトークンを見分けるために使う |
| `last_used_at` | DATETIME | NULLABLE | 最終利用時刻 |
| `expires_at` | DATETIME | NOT NULL | 有効期限（期間の長さは 4.5.7 で未決） |
| `created_at` / `updated_at` | DATETIME | NOT NULL | |

**`notebooks`**

| カラム名 | 型 | 制約 | 説明 |
| :--- | :--- | :--- | :--- |
| `id` | BIGINT UNSIGNED | PK, AUTO_INCREMENT | |
| `user_id` | BIGINT UNSIGNED | FK → `users.id`, NOT NULL, INDEX | |
| `title` | VARCHAR(255) | NOT NULL | ノートブック表示名（LLM提案 or ユーザー編集） |
| `goal_text` | TEXT | NOT NULL | ユーザーが入力・確定した学習ゴールの原文 |
| `difficulty` | ENUM('light','standard','deep') | NOT NULL | F-003 の難易度選択値 |
| `status` | ENUM('generating','ready','failed') | NOT NULL, DEFAULT 'generating' | シラバス生成の進行状態 |
| `created_at` / `updated_at` | DATETIME | NOT NULL | |

**`syllabus_nodes`**

| カラム名 | 型 | 制約 | 説明 |
| :--- | :--- | :--- | :--- |
| `id` | BIGINT UNSIGNED | PK, AUTO_INCREMENT | |
| `notebook_id` | BIGINT UNSIGNED | FK → `notebooks.id`, NOT NULL, INDEX | |
| `parent_node_id` | BIGINT UNSIGNED | FK → `syllabus_nodes.id`, NULLABLE, INDEX | ドリルダウンの親ノード（F-007） |
| `title` | VARCHAR(255) | NOT NULL | |
| `summary` | TEXT | NOT NULL | AIによる概要文（F-011） |
| `route_type` | ENUM('main','sub') | NOT NULL | メインルート／サブクエスト（F-006） |
| `importance_score` | FLOAT | NOT NULL, DEFAULT 0 | LLMが付与するゴール到達への重要度（0〜1）．コンパス候補の強調順に使う（4.2.8） |
| `depth_level` | INT UNSIGNED | NOT NULL, DEFAULT 0 | ドリルダウンの階層深さ（0が最上位） |
| `related_main_node_id` | BIGINT UNSIGNED | FK → `syllabus_nodes.id`, NULLABLE | `route_type='sub'` の場合の紐付け先メインノード |
| `embedding` | JSON | NULLABLE | クロスノートブックリンク検出用の埋め込みベクトル（4.2.7で保存，`route_type='main'` のみ） |
| `skip_recommended` | BOOLEAN | NOT NULL, DEFAULT FALSE | アセスメント結果による既習スキップ推奨フラグ（F-004） |
| `created_at` / `updated_at` | DATETIME | NOT NULL | |

**`cross_notebook_links`**（他ノートブックとの関連提案・接続）

| カラム名 | 型 | 制約 | 説明 |
| :--- | :--- | :--- | :--- |
| `id` | BIGINT UNSIGNED | PK, AUTO_INCREMENT | |
| `user_id` | BIGINT UNSIGNED | FK → `users.id`, NOT NULL, INDEX | リンクはユーザー単位（他ユーザーのノートブックとは接続しない） |
| `source_node_id` | BIGINT UNSIGNED | FK → `syllabus_nodes.id`, NOT NULL, INDEX | 提案の起点となった新規ノード（4.2.7で生成直後に検出） |
| `target_node_id` | BIGINT UNSIGNED | FK → `syllabus_nodes.id`, NOT NULL, INDEX | 関連が検出された既存ノード（別ノートブック） |
| `similarity_score` | FLOAT | NOT NULL | 検出時のEmbedding類似度（4.2.7） |
| `status` | ENUM('proposed','accepted','rejected') | NOT NULL, DEFAULT 'proposed' | ユーザーの応答状態 |
| `responded_at` | DATETIME | NULLABLE | ユーザーが承認／却下した時刻 |
| `created_at` / `updated_at` | DATETIME | NOT NULL | |
| UNIQUE制約 | | `(source_node_id, target_node_id)` | 同一ペアへの重複提案を禁止 |

`cross_notebook_links` は `syllabus_edges` と異なり，(1) 異なるノートブックのノード間のみを結ぶ，(2) `status` によってユーザーの意思（提案中／承認済／却下済）を保持する，という2点が特徴である．承認された（`status='accepted'`）リンクのみが学習マップ上で「他ノートブックへの接続」として表示され，`proposed` のままのリンクはユーザーへの提案表示にのみ使われる．ノード自体の統合は一切行わない．

**`syllabus_edges`**

| カラム名 | 型 | 制約 | 説明 |
| :--- | :--- | :--- | :--- |
| `id` | BIGINT UNSIGNED | PK, AUTO_INCREMENT | |
| `from_node_id` | BIGINT UNSIGNED | FK → `syllabus_nodes.id`, NOT NULL, INDEX | 前提ノード |
| `to_node_id` | BIGINT UNSIGNED | FK → `syllabus_nodes.id`, NOT NULL, INDEX | 後続ノード |
| `relation_type` | ENUM('required','supplementary') | NOT NULL, DEFAULT 'required' | 必須前提／補足 |
| UNIQUE制約 | | `(from_node_id, to_node_id)` | 同一方向の重複エッジを禁止 |

**`assessment_questions` / `assessment_answers`**

| テーブル | 主なカラム | 説明 |
| :--- | :--- | :--- |
| `assessment_questions` | `id`, `notebook_id`, `question_text`, `choices`（JSON） | F-004 で生成される3〜5問の質問 |
| `assessment_answers` | `id`, `question_id`, `answer_value`, `target_node_id`（NULLABLE） | 回答結果．`target_node_id` は回答が既習判定に紐づく場合のノード参照 |

**`progress_statuses`**

| カラム名 | 型 | 制約 | 説明 |
| :--- | :--- | :--- | :--- |
| `id` | BIGINT UNSIGNED | PK, AUTO_INCREMENT | |
| `node_id` | BIGINT UNSIGNED | FK → `syllabus_nodes.id`, NOT NULL, UNIQUE | 1ノード1レコード |
| `status` | ENUM('not_started','in_progress','completed') | NOT NULL, DEFAULT 'not_started' | |
| `milestone_artifact_url` | VARCHAR(2048) | NULLABLE | F-010 のマイルストーン成果物リンク |
| `completed_at` | DATETIME | NULLABLE | 現在地の決定に使う（4.2.8） |
| `created_at` / `updated_at` | DATETIME | NOT NULL | `updated_at` は学習中ノードが複数ある場合の現在地の決定に使う（4.2.8） |

`syllabus_nodes` と `syllabus_edges` は同一ノートブック内で完結するグラフを表現し，学習マップ（そのままのグラフ描画）はこの2テーブルのみから導出でき，コンパスはこれに `progress_statuses` を加えて導出できる．他ノートブックとの関連は `cross_notebook_links` として明確に別テーブルに分離しており，ノードの同一性を仮定しないため，学習マップの実装が単一ノートブックの範囲を超えて複雑化することを防いでいる．なお `syllabus_edges` はDBレベルでは循環参照を防止できないため，4.2.4 のシラバス生成時バリデーションで DAG 性（非巡回性）を保証する運用とする．

### 4.2 主要機能のアルゴリズム設計

#### 4.2.1 ゴール具体化・提案（F-002）

ユーザー入力の抽象度をLLMに判定させ，「具体的な学習ゴールとして成立するか」を `is_concrete: boolean` で返させる．`false` の場合，同一プロンプト内で3件のゴール候補（`title`, `description`）を生成させ，選択式UIに渡す．ユーザーが独自ゴールを再入力した場合は再判定を1回のみ行い，無限ループを避けるため2回目以降は入力をそのままゴールとして採用する．

```
function resolveGoal(rawInput, retryCount = 0):
    result = callLLM(GOAL_CLASSIFY_TEMPLATE, input=rawInput)
    # result: { is_concrete: bool, candidates: [{title, description}] (最大3件) }

    if result.is_concrete == true:
        return Goal(text=rawInput, source="user_direct")

    if retryCount >= 1:
        # 2周目以降は判定をスキップし、そのまま採用（無限ループ防止）
        return Goal(text=rawInput, source="user_forced")

    presentToUser(result.candidates)  # 選択式UIへ
    return AWAIT_USER_SELECTION       # ユーザー選択 or 再入力を待つ
```

#### 4.2.2 難易度選択によるプロンプト制約（F-003）

「ライト／スタンダード／ディープ」の選択値を，シラバス生成プロンプトの `max_depth`（ドリルダウン階層数），`node_count_target`（メインルートのノード数目安），`sub_quest_ratio`（サブクエストの生成比率）という3つのパラメータにマッピングする．マッピング値はソースコードから切り離し，4.3.2 で述べるプロンプトテンプレート管理の対象とする．

初期値の目安（プロンプトテンプレート側の設定ファイルで管理する想定値）:

| 難易度 | `max_depth` | `node_count_target`（メインルート） | `sub_quest_ratio` |
| :--- | :--- | :--- | :--- |
| ライト | 1（ドリルダウンなし相当） | 5〜8 | 0.1（ほぼ寄り道なし） |
| スタンダード | 2 | 8〜15 | 0.3 |
| ディープ | 3 | 15〜25 | 0.5（背景理論まで深掘り） |

```
function buildGenerationParams(difficulty):
    config = loadPromptConfig("difficulty_mapping")  # 外部設定ファイルから取得
    return config[difficulty]
    # => { max_depth, node_count_target, sub_quest_ratio }
```

#### 4.2.3 前提知識アセスメント（F-004）

決定したゴールに基づき，LLMに3〜5問の確認質問（多肢選択または自己申告形式）を生成させる．回答結果は `assessment_answers` に保存し，シラバス生成プロンプトへ「ユーザーが既に習得済みの前提知識」として渡す．LLMはこれを踏まえて該当ノードを生成しない，または `skip_recommended: true` フラグ付きで生成する．

#### 4.2.4 シラバスJSON動的生成（F-011）

LLMへは，ゴール・難易度パラメータ・アセスメント結果を含むプロンプトを送信し，ノード（`id`, `title`, `summary`, `prerequisites: [id]`, `route_type`, `importance_score`）の配列をJSON形式で返させる．出力はJSON Schema による構造化出力（またはツール呼び出し形式）を用いて形式を強制し，パース失敗時のリトライ戦略（最大2回）をバックエンド側に実装する．

#### 4.2.5 リニア（一本道）変換アルゴリズム（廃止）

v0.5.0 で一本道ビューを廃止したため，本アルゴリズム（トポロジカルソートによる `display_order` の確定）は廃止した（ReqDef F-005, F-008）．学習の進め方は 4.2.8 のコンパスで示す．

#### 4.2.6 ドリルダウン展開（F-007）

学習マップの初期表示では `depth_level = 0` のノードのみを描画し，ユーザーが地点を選んだ際に `parent_node_id` が一致する子ノード群とその間のエッジを `GET /api/nodes/:id/children`（4.3.1）で取得し，その地点の内部として展開する．子ノード群も学習マップと同じくグラフのまま表示する．

#### 4.2.7 クロスノートブックリンク：即時提案処理

シラバス生成（4.2.4）のストリーミング中，`route_type = main` の各ノードが1件確定するたびに，同一ユーザーの他ノートブックに属する既存ノードとの関連度を即時に検出する．関連度の判定には埋め込みベクトルによる類似度検索を用いるが，今回の想定規模（ReqDef 5.2：通常100 DAU／ピーク1,000 DAU）ではユーザーあたりのノード数も小さいため，専用のベクトルDB／ベクトルインデックスは導入せず，埋め込み計算のみ外部Embedding APIに委ね，類似度計算自体はアプリケーション層でのコサイン類似度計算で済ませる（5章の代替案として詳細化）．統合ではなく「提案」に留めるため，本処理はノードや既存データを変更せず，`cross_notebook_links` に `status='proposed'` のレコードを追加するのみである．

```
function proposeCrossNotebookLinks(newNode, currentNotebookId, userId):
    # newNode: 生成直後の syllabus_node（route_type = main）
    embedding = callEmbeddingAPI(newNode.title + "\n" + newNode.summary)
    saveEmbedding(newNode, embedding)  # syllabus_nodes.embedding に保存（後続ノードとの比較にも再利用）

    # 同一ユーザーの「他ノートブック」に属する既存ノードのみを比較対象にする
    candidateNodes = loadMainNodesExcludingNotebook(userId, excludeNotebookId=currentNotebookId)

    SIMILARITY_THRESHOLD = 0.80  # 初期値。提案なので統合より緩めに設定（5章・9章参照）

    for candidate in candidateNodes:
        score = cosineSimilarity(embedding, candidate.embedding)
        if score >= SIMILARITY_THRESHOLD:
            createCrossNotebookLink(
                userId=userId,
                sourceNodeId=newNode.id,
                targetNodeId=candidate.id,
                similarityScore=score,
                status="proposed"
            )
            # 1つのノードに対して複数の提案が発生してもよい（上限は運用で調整、9章参照）
```

* ユーザーが提案を確認し `PATCH /api/cross_notebook_links/:id`（4.3.1）で承認すると `status` が `accepted` に更新され，学習マップ上で他ノートブックへの接続として表示される．却下すると `rejected` となり，以後同じペアが再提案されることはない（UNIQUE制約により）．
* 類似度の閾値（`SIMILARITY_THRESHOLD`）は初期値の仮置きであり，実データでの検証が必要（9章のオープンな論点）．統合ではなく提案であるため，4.2.7時点では「誤提案（的外れな提案でユーザーを煩わせる）」の方が「過小提案（気づきの機会を逃す）」より実害が大きいと判断し，閾値は保守的（高め）に設定する方針としている．
* サブクエスト（`route_type = sub`）は提案の対象外とし，メインルートのノードのみを比較対象とする．この方針は9章の議論と合わせて再検討の余地がある．

#### 4.2.8 現在地とコンパスの決定（F-013）

コンパスは「学習マップ上の現在地から，今進める方角（次に学べるノード）をすべて指す」ものであり，順序情報や座標は持たず，`syllabus_edges` と `progress_statuses` から都度導出する．対象は `depth_level = 0` のメインルートノードとする．

```
function resolveCompass(notebookId):
    nodes = loadMainNodes(notebookId, depthLevel=0)

    # 現在地: 学習中（複数なら最も最近更新したもの）→ 直近に完了したもの → スタート地点（null）
    inProgress = nodes where node.progress.status == "in_progress"
    completed  = nodes where node.progress.status == "completed"
    if inProgress is not empty:
        current = maxBy(inProgress, node.progress.updated_at)
    else if completed is not empty:
        current = maxBy(completed, node.progress.completed_at)
    else:
        current = null  # スタート地点

    # 進める方角: 必須の前提ノードがすべて完了している未完了ノード
    candidates = nodes where node.progress.status != "completed"
                     and all(prereq.progress.status == "completed"
                             for prereq in requiredMainPrerequisites(node))

    # DAG であるため，未完了ノードが残っていれば候補は必ず1件以上存在する
    if all(node.progress.status == "completed" for node in nodes):
        return { currentNodeId: current?.id, candidates: [], isGoalReached: true }

    # 強調表示のため importance_score の高い順，同点は生成順（id）で並べる
    sortBy(candidates, -node.importance_score, node.id)
    return { currentNodeId: current?.id, candidates: candidates, isGoalReached: false }
```

* 必須の前提ノードとは，`relation_type = 'required'` のエッジで結ばれたメインルートの前提ノードを指す．`supplementary` のエッジやサブクエストの完了状態は判定に使わない．
* 候補が複数ある場合はすべてを「進める方角」として示し，どれに進むかはユーザーが選ぶ．`importance_score` は強調表示のためだけに使い，候補の絞り込みには使わない．
* 学習中のノード自体も未完了であるため候補に含まれる．
* サブクエスト（`route_type = sub`）は寄り道であり，現在地にも候補にもならない．
* 現在地・候補はバックエンドで決定し，フロントエンドでは再計算しない．進捗更新（`PATCH /api/nodes/:id/progress`）のたびに再計算し，レスポンスに最新のコンパス情報を含める．

### 4.3 インタフェース設計

#### 4.3.1 クライアント（フロントエンド・CLI）–バックエンドAPI

REST API を基本としつつ，シラバス生成のみストリーミング（Server-Sent Events）で提供する．フロントエンドと CLI（4.5）は同じ API を利用する．CLI は `Authorization: Bearer <token>` ヘッダーで認証する（4.5.4）．

| エンドポイント | 概要 |
| :--- | :--- |
| `POST /api/auth/tokens` | メールアドレスとパスワードで認証し，CLI 用のトークンを発行する（4.5.4，新規）． |
| `DELETE /api/auth/tokens/current` | リクエストに使ったトークンを失効させる（4.5.4，新規）． |
| `GET /api/notebooks` | ログインユーザーのノートブック一覧を取得（F-012，新規）． |
| `POST /api/notebooks` | ノートブック（学習テーマ）の新規作成． |
| `POST /api/notebooks/:id/goal_suggestions` | 入力に対するゴール候補提案（F-002）． |
| `POST /api/notebooks/:id/assessment` | 前提知識アセスメントの質問取得・回答送信（F-004）． |
| `POST /api/notebooks/:id/syllabus` (SSE) | シラバス生成をストリーミングで開始し，ノード単位で逐次イベントを返す（F-011）．4.2.7で検出したクロスノートブックリンクの提案は，該当ノードのイベントの直後に独立したイベントとして返す．イベント形式は本節の「SSE イベント形式」を参照． |
| `GET /api/notebooks/:id/map` | 当該ノートブックの `depth_level = 0` のシラバスグラフ（学習マップ）を，承認済みクロスノートブックリンクとコンパス情報（4.2.8）を含めて取得（新規）． |
| `GET /api/nodes/:id/children` | ドリルダウン（F-007）．指定ノードの子ノード群とその間のエッジをグラフとして取得（新規）． |
| `GET /api/cross_notebook_links?status=proposed` | ユーザーに提示すべき未応答の提案一覧を取得（新規）． |
| `PATCH /api/cross_notebook_links/:id` | 提案の承認／却下（`status` を `accepted` / `rejected` に更新，新規）． |
| `PATCH /api/nodes/:id/progress` | ノードの進捗ステータス更新（F-010）．レスポンスに更新後のコンパス情報（4.2.8）を含める． |

**`POST /api/notebooks` レスポンス例**

```json
{
  "id": 123,
  "title": "AIエンジニアリング入門",
  "goal_text": "AIについて深く知りたい",
  "difficulty": "standard",
  "status": "generating",
  "created_at": "2026-07-03T10:00:00+09:00"
}
```

**`POST /api/auth/tokens` リクエスト／レスポンス例**

```json
{ "email": "user@example.com", "password": "********", "name": "my-laptop" }
```

```json
{ "token": "cmp_3f9a...", "expires_at": "2027-01-04T10:00:00+09:00" }
```

**`GET /api/notebooks` レスポンス例**

```json
{
  "notebooks": [
    { "id": 123, "title": "AIエンジニアリング入門", "difficulty": "standard", "status": "ready", "updated_at": "2026-07-03T10:05:00+09:00" },
    { "id": 124, "title": "データ分析基礎", "difficulty": "light", "status": "ready", "updated_at": "2026-06-20T21:30:00+09:00" }
  ]
}
```

**`GET /api/notebooks/:id/map` レスポンス例**

```json
{
  "notebook_id": 123,
  "graph": {
    "nodes": [
      { "id": 501, "title": "統計学の基礎", "route_type": "main", "importance_score": 0.8, "has_children": true, "progress": "completed" },
      { "id": 502, "title": "線形代数の基礎", "route_type": "main", "importance_score": 0.9, "has_children": false, "progress": "not_started" },
      { "id": 503, "title": "微分の基礎", "route_type": "main", "importance_score": 0.6, "has_children": false, "progress": "not_started" },
      { "id": 620, "title": "ベイズ統計への招待", "route_type": "sub", "related_main_node_id": 501, "importance_score": 0.3, "has_children": false, "progress": "not_started" }
    ],
    "edges": [
      { "from": 501, "to": 502, "relation_type": "required" },
      { "from": 501, "to": 503, "relation_type": "required" }
    ]
  },
  "compass": {
    "current_node_id": 501,
    "candidates": [
      { "node_id": 502, "importance_score": 0.9 },
      { "node_id": 503, "importance_score": 0.6 }
    ],
    "is_goal_reached": false
  },
  "cross_notebook_links": [
    {
      "link_id": 8801,
      "source_node_id": 501,
      "target": {
        "notebook_id": 124,
        "notebook_title": "データ分析基礎",
        "node_id": 733,
        "title": "統計学の基礎"
      },
      "status": "accepted"
    }
  ]
}
```

**`GET /api/cross_notebook_links?status=proposed` レスポンス例**

```json
{
  "proposals": [
    {
      "link_id": 8802,
      "similarity_score": 0.83,
      "source": { "notebook_id": 123, "notebook_title": "AIエンジニアリング入門", "node_id": 502, "title": "線形代数の基礎" },
      "target": { "notebook_id": 130, "notebook_title": "行動経済学入門", "node_id": 890, "title": "ベクトルと行列の基本" }
    }
  ]
}
```

**`PATCH /api/cross_notebook_links/:id` リクエスト例**

```json
{ "status": "accepted" }
```

**`POST /api/notebooks/:id/syllabus` SSE イベント形式**

レスポンスの `Content-Type` は `text/event-stream` とする．各イベントは `event:` 行と `data:` 行（JSON を1行で記載）からなり，空行で区切る（4.5.6 の CLI の受信方式と同じ）．CLI は `Authorization: Bearer <token>` で認証する（4.5.4）．ブラウザ側の SSE 認証はフロントエンドの認証方式（9章）が未決のため未定とする．なお，ブラウザの `EventSource` は POST やリクエストヘッダーを指定できないため，フロントエンドでは `fetch` のストリーム読み取り等が必要になる．

| イベント名 | 送信タイミング | 概要 |
| :--- | :--- | :--- |
| `node` | ノード1件分の JSON が確定し，DB に保存した直後 | 完成した1ノード．トークン断片は送らない（4.3.2）． |
| `link_proposal` | 4.2.7 で提案が作られた直後（該当する `node` イベントの後） | クロスノートブックリンクの提案1件．`node` には入れ子にしない． |
| `done` | 全ノードの生成が完了し，ノートブックを `ready` にした後 | 終端イベント． |
| `error` | 生成を続けられなくなったとき | 終端イベント． |

* `node` の `data` は次の項目を持つ．`id` は DB 保存後のノード ID であり，`prerequisites` の各要素も保存後の ID とする．`GET /api/notebooks/:id/map` のノード表現と共通する項目（`id`，`title`，`route_type`，`importance_score` など）は，同じ名前・意味とする．埋め込みベクトルは含めない．

  | 項目 | 型 | 説明 |
  | :--- | :--- | :--- |
  | `id` | number | `syllabus_nodes.id` |
  | `title` | string | ノードのタイトル |
  | `summary` | string | ノードの要約 |
  | `prerequisites` | number[] | 前提ノードの ID（4.2.4） |
  | `route_type` | string | `main` / `sub` |
  | `importance_score` | number | 0〜1 |
  | `depth_level` | number | ドリルダウンの階層（F-007） |
  | `related_main_node_id` | number \| null | `route_type = sub` の場合の紐付け先メインノード |

* `link_proposal` の `data` は `GET /api/cross_notebook_links?status=proposed` の `proposals` の要素と同じ形（`link_id`，`similarity_score`，`source`，`target`）とする．`source.node_id` は直前に送った `node` の `id` と一致する．
* `done` の `data` は `notebook_id`，`status`（`"ready"` 固定），`node_count`（保存したノード数）を持つ．
* `error` の `data` は `code`，`message`，`retryable` を持つ．`message` は利用者に表示してよい文言とし，内部例外の詳細や API キーは含めない．`retryable` はクライアントが生成のやり直しを提案してよいかを示す．

  | `code` | 意味 | `retryable` |
  | :--- | :--- | :--- |
  | `parse_failed` | LLM 出力のパースに失敗し，リトライ上限（最大2回，4.2.4）を超えた | `true` |
  | `invalid_syllabus` | 循環や未知の前提 ID など DAG の検証エラー．該当エッジを黙って除去・修正しない | `true` |
  | `llm_api_error` | LLM API／Embedding API の呼び出しに失敗した | `true` |
  | `internal_error` | 上記以外のサーバー内部エラー | `false` |

* `done` と `error` は終端イベントであり，サーバーはどちらかを送った後に接続を閉じる．クライアントは終端イベントを受け取らずに接続が切れた場合，生成が完了していないものとして扱う．切断時の再接続・再開の挙動は未決（9章）のため，`id:` 行による再開は定義しない．
* 接続維持のため，サーバーはコメント行（`: keep-alive`）を送ってよい．クライアントはコメント行を無視する．

**`POST /api/notebooks/:id/syllabus` SSE レスポンス例（正常終了）**

```
event: node
data: {"id":501,"title":"統計学の基礎","summary":"データの要約と確率の基本を学ぶ","prerequisites":[],"route_type":"main","importance_score":0.8,"depth_level":0,"related_main_node_id":null}

event: link_proposal
data: {"link_id":8801,"similarity_score":0.86,"source":{"notebook_id":123,"notebook_title":"AIエンジニアリング入門","node_id":501,"title":"統計学の基礎"},"target":{"notebook_id":124,"notebook_title":"データ分析基礎","node_id":733,"title":"統計学の基礎"}}

event: node
data: {"id":502,"title":"線形代数の基礎","summary":"ベクトルと行列の基本を学ぶ","prerequisites":[501],"route_type":"main","importance_score":0.9,"depth_level":0,"related_main_node_id":null}

: keep-alive

event: node
data: {"id":620,"title":"ベイズ統計への招待","summary":"確率の更新という考え方に触れる","prerequisites":[501],"route_type":"sub","importance_score":0.3,"depth_level":0,"related_main_node_id":501}

event: done
data: {"notebook_id":123,"status":"ready","node_count":3}

```

**`POST /api/notebooks/:id/syllabus` SSE レスポンス例（エラー終了）**

```
event: node
data: {"id":501,"title":"統計学の基礎","summary":"データの要約と確率の基本を学ぶ","prerequisites":[],"route_type":"main","importance_score":0.8,"depth_level":0,"related_main_node_id":null}

event: error
data: {"code":"parse_failed","message":"シラバスの生成結果を解析できませんでした．時間をおいて再度お試しください．","retryable":true}

```

> 学習マップの画面遷移・URL構成（例：ノートブック一覧から学習マップへどう遷移するか，提案をどこで通知するか）は 9章の論点確定後に追記する．

#### 4.3.2 バックエンド–LLM API

* プロンプトテンプレートはソースコードから切り離して管理する（ReqDef 5.4）．具体的には，YAML等の外部ファイル，または LangChain/LangSmith 等のオーケストレーションツールでのバージョン管理を想定し，無停止でのA/Bテスト・チューニングを可能にする．
* LLM APIへのリクエスト時には，各社が提供する「学習利用オプトアウト」設定を必須パラメータとして常に付与する（ReqDef 5.3）．
* ストリーミングレスポンスは，LLM側のトークン単位のストリームをバックエンドで「1ノード分のJSONが確定した時点」でバッファリングし直し，フロントエンドへはノード単位のSSEイベントとして中継する．これにより，フロントエンドはトークン断片ではなく意味のある単位で描画できる．イベント名とペイロードの形式は 4.3.1 の「SSE イベント形式」に定める．
* クロスノートブックリンクの検出（4.2.7）で使用する埋め込み計算も，シラバス生成と同じLLMベンダーのEmbedding APIを利用し，APIキー管理・オプトアウト設定は同一の仕組みに乗せる．

### 4.4 UI/UX設計方針（認知負荷の軽減）

ReqDef 5.1 が求める「認知負荷の軽減」を満たすため，フロントエンドは学習マップを以下の方針で構成する．学習マップは「全体を俯瞰できる地図」であると同時に，コンパスによって「今どこへ進めるか」に意識を集中させる画面と位置付ける．

**学習マップ**

* 初期表示では `depth_level = 0` の地点のみを描き，個々のノードの詳細（`summary` 等）は出さず，タイトルと繋がりのみを見せることで情報量を制御する．詳細は地点を選んだときに表示する．
* 初期表示の視点は現在地とその周辺（現在地の前提ノード，コンパスの候補）に寄せ，全体はユーザーが能動的に広げて眺める．
* 地点を選ぶとその内部（子ノード）を展開する（F-007，4.2.6）．
* サブクエストは，関連するメインルートの地点から伸びる脇道として描く（F-006）．
* 新しい章の開始時は，既習の地点から新しい地点へ道がつながるアニメーション演出を行う（F-009）．
* 承認済みのクロスノートブックリンク（`cross_notebook_links.status='accepted'`）を持つノードには，他ノートブックへの接続を示す視覚的な印（衛星アイコン等）を付け，選択すると接続先ノートブックのタイトルとノードが表示される．
* 未応答の提案（`status='proposed'`）は，学習マップ内で控えめに（例えば点線や薄い色で）示すか，別途通知として提示するかは9章で検討中．いずれの場合も，提案はユーザーが明示的に承認するまでデータ上のリンクとして確定しないことを画面上で明確にする．

**コンパス**

* 学習マップ上で現在地を明示し，コンパスが「進める方角」（4.2.8 の候補）をすべて指し示す．`importance_score` の最も高い候補を強調し，迷ったときの目安にする．
* 候補を選ぶとその地点の詳細を表示し，学習を開始できる（進捗を `in_progress` に更新）．
* 現在地がない場合（スタート地点）は，前提ノードを持たない地点が候補として示される．
* 全ノード完了時（`is_goal_reached = true`）は，ゴール到達を示す表示に切り替える．

### 4.5 CLI設計（F-014）

#### 4.5.1 方針

* CLI はフロントエンドと同列の「バックエンドAPIのクライアント」であり，4.3.1 の API のみを利用する．コンパス（4.2.8），DAG の検証，クロスノートブックリンクの検出といった業務ロジックは持たず，バックエンドが返した結果をそのまま表示する．これにより，フロントエンドと CLI で表示内容が食い違わない．
* 外部LLM API・Embedding API を直接呼ばず，それらのAPIキーも保持しない（ReqDef 5.3）．
* Go の標準ライブラリ（`flag`，`net/http`，`encoding/json`，`bufio` 等）のみで実装し，外部パッケージに依存しない．単一の実行ファイルとして配布しやすく（ReqDef 5.1），依存パッケージの更新・脆弱性対応の負担もなくなる．
* 接続先のバックエンドは環境変数 `CAMPASS_API_URL` で指定する．

#### 4.5.2 構成

```
cli/
├── go.mod
├── cmd/campass/main.go   # エントリポイント．サブコマンドの振り分けのみ
└── internal/
    ├── command/          # コマンド層：引数解析・対話入力
    ├── api/              # API通信層：REST，SSE 受信，トークン付与
    ├── render/           # 表示層：学習マップ・コンパス・提案のテキスト出力
    └── config/           # 接続先とトークンの読み書き
```

レイヤーの役割は基本設計書 2.4，コマンド一覧は基本設計書 3.5 を参照する．

#### 4.5.3 ノートブック作成の対話フロー（`campass new`）

3.2 のステップ1〜6を，ターミナル上の対話として順に行う．

1. 興味を自由入力させ，ゴール候補（F-002）が返った場合は番号付きで表示して選ばせる．再入力の扱いは 4.2.1 に従い，バックエンドが判定する．
2. 難易度（ライト／スタンダード／ディープ）を番号で選ばせる（F-003）．
3. アセスメントの質問（F-004）を1問ずつ表示し，回答を送信する．
4. `POST /api/notebooks/:id/syllabus` の SSE を受信し，ノードが1件届くたびにタイトルと種別（メイン／サブ）を1行で表示する（4.5.6）．`link_proposal` イベントが届いた場合は，「提案」であることが分かる形で表示する．ここでは承認しない．
5. ストリームが終わったら `GET /api/notebooks/:id/map` を呼び，学習マップとコンパスを表示する（4.5.5）．

#### 4.5.4 認証

* `campass login` はメールアドレスとパスワードを入力させ，`POST /api/auth/tokens` でトークンを取得する．バックエンドはトークンの SHA-256 ハッシュのみを `api_tokens` に保存し，平文はこのレスポンスでのみ返す．
* CLI はトークンを `os.UserConfigDir()` 配下の `campass/credentials.json` に，所有者のみ読み書きできる権限（0600）で保存する．
* 以後のリクエストには `Authorization: Bearer <token>` を付ける．`401` が返った場合は `campass login` のやり直しを促す．
* `campass logout` は `DELETE /api/auth/tokens/current` でトークンを失効させてから，ローカルのファイルを削除する．
* Cookie セッションではなくトークン方式とする理由は 5.6 を参照する．

#### 4.5.5 学習マップとコンパスのテキスト表示（`campass map`）

一本道ビューは廃止されているため（4.2.5），CLI でもノードを「学習する順番」に見える一列として表示しない．表示はコンパスを主とし，グラフは各ノードの前提関係として示す．

```
コンパス
  現在地: 統計学の基礎 (#501)
  進める方角:
    ★ 線形代数の基礎 (#502)  重要度 0.90
      微分の基礎     (#503)  重要度 0.60

学習マップ
  #501 統計学の基礎    [完了]   ⇄ データ分析基礎「統計学の基礎」
       └ 寄り道 #620 ベイズ統計への招待 [未着手]
  #502 線形代数の基礎  [未着手] ← 前提: #501
  #503 微分の基礎      [未着手] ← 前提: #501
```

* 「進める方角」は `compass.candidates` の並び（4.2.8）のまま表示し，先頭の候補に印（★）を付ける．CLI では並べ替えない．
* 学習マップの各行は，ノードとその必須の前提ノード（`relation_type = 'required'`）を示す．`supplementary` のエッジは「補足:」として別に示す．行の並びは API レスポンスの順であり，学習順の意味を持たない．
* サブクエストは，`related_main_node_id` のメインノードの下に「寄り道」として字下げして表示する（F-006）．
* 承認済みのクロスノートブックリンクには印（⇄）と接続先を付ける．未応答の提案は `campass links` で確認する．
* `is_goal_reached` が `true` の場合は，候補の代わりにゴール到達を表示する．
* `campass show <node_id>` は `GET /api/nodes/:id/children` の結果を同じ形式で表示する（F-007）．

#### 4.5.6 シラバス生成のストリーミング受信

* SSE のレスポンスを `bufio.Scanner` で1行ずつ読み，空行までの `data:` 行をつなげて1イベントとし，JSON としてデコードする．`event:` 行のイベント名で処理を分岐する（形式は 4.3.1）．`node` は1イベントが1ノードに対応するため（4.3.2），デコードできたらすぐに表示する．`link_proposal` は「提案」として表示する（4.5.3）．
* `bufio.Scanner` は既定で1行64KBまでしか読めないため，`summary` の長いノードに備えて上限を広げる．
* `done` を受け取ったら受信を終えて `GET /api/notebooks/:id/map` に進む．`error` を受け取ったら `code` と `message` を表示して終了する．どちらも受け取らずに接続が切れた場合は，生成が完了していないものとしてエラー表示する．
* `:` で始まるコメント行は無視する．未知のイベント名は，エラーにせず読み飛ばす．
* JSON としてデコードできないイベントは，黙って捨てずにエラーとして表示する．

#### 4.5.7 未決事項

CLI に関わる未決事項は 9章にまとめる（ノード詳細の取得，生成中の中断，認証まわり，配布方法）．

## 5. 検討した代替案（Alternatives Considered）

### 5.1 グラフ表現：グラフDB vs リレーショナルDB（ノード・エッジ方式）

* **案A（採用）**: MySQL 上にノード・エッジテーブルを設けてグラフを表現する．
  * 利点: 既存の技術スタック（MySQL）をそのまま使え，スモールスタート（100〜1,000 DAU）の規模では十分な性能が出せる．ノートブック単位でのトランザクション管理も容易．
  * 欠点: 深い階層の依存関係探索（多段階のJOIN）はグラフDBほど高速ではない．
* **案B（不採用）**: Neo4j 等の専用グラフDBを導入する．
  * 利点: 依存関係の探索・パス検索がネイティブに高速．
  * 欠点: ReqDef 6章で技術スタックがMySQLと明記されており，インフラ構成が複雑化する．初期リリース規模（ReqDef 5.2）に対して過剰投資であると判断し，不採用とした．ただし「学習マップ」実装時にノード数・エッジ数が大幅に増加する場合は再検討の余地を残す．

### 5.2 シラバス生成方式：一括生成 vs ストリーミング生成

* **案A（採用）**: LLMにノード単位でストリーミング生成させ，逐次DB保存・逐次UI描画する．
  * 利点: ReqDef 5.2 が要求する体感待ち時間の最小化を満たす．生成途中でユーザーが最初の一歩を読み始められる．
  * 欠点: ノード単位でのJSONパース処理，および途中でエラーが起きた場合のロールバック処理が複雑になる．
* **案B（不採用）**: シラバス全体を一括生成してから一度にレスポンスする．
  * 利点: 実装がシンプルで，JSON全体の整合性検証がしやすい．
  * 欠点: 生成に数十秒かかる間ユーザーが何も見えない状態になり，ReqDef 5.2 の要件を満たさない．

### 5.3 一本道変換のタイミング：生成直後変換 vs 表示時変換（v0.5.0 で廃止）

> v0.5.0 で一本道ビューと `display_order` を廃止したため，本検討は不要となった．経緯の記録として残す．

* **案A（採用）**: シラバス生成直後にバックエンドでリニア変換を行い，`display_order` として永続化する．
  * 利点: フロントエンドは常に確定済みの順序を受け取ればよく，表示ロジックがシンプルになる．同一シラバスを複数回開いても順序が一貫する．
* **案B（不採用）**: グラフ構造のみを保存し，表示の都度フロントエンドでトポロジカルソートする．
  * 利点: バックエンドの実装がシンプル．
  * 欠点: 同順位ノードの順序がリクエストごとに揺れる可能性があり，「一本道」という体験の一貫性を損なう．また，進捗管理（F-010）とノードの並び順を紐付けにくい．

### 5.4 クロスノートブックリンクの関連度判定：Embedding類似度 vs 別方式

* **案A（採用）**: 外部Embedding APIでベクトル化し，アプリケーション層でのコサイン類似度によって他ノートブックの既存ノードとの関連を検出し，ユーザーへの提案として`cross_notebook_links`に記録する（4.2.7）．
  * 利点: 「統計学の基礎」「統計の基本」のような表記揺れをある程度吸収できる．ルールベースでは対応しきれない言い回しの違いに強い．専用ベクトルDBを導入しないため，今回の想定規模（ReqDef 5.2）に対して過剰投資にならない．統合ではなく提案に留めるため，誤検出があってもユーザーが却下すれば実害が小さい．
  * 欠点: 閾値（4.2.7 では暫定0.80）のチューニングが必要で，的外れな提案（誤検出）・気づきの機会を逃す（過小検出）のトレードオフが残る．また，新規ノードが確定するたびに同一ユーザーの他ノートブック全ノードをロードして比較するため，将来ノート・ノード数が大きく増えた場合はスケールしない（9章）．
* **案B（不採用）**: LLMにシラバス生成と同時に「他ノートブックの既存ノード一覧」を渡し，関連候補を自己判断させる．
  * 利点: 追加のAPI呼び出し（Embedding計算）が不要で，文脈（ゴール自体の違い等）まで踏まえた柔らかい判断が可能．
  * 欠点: 既存ノード一覧をプロンプトに含める必要があり，ノート・ノード数が増えるとプロンプト長が肥大化しコスト・レイテンシが悪化する．LLMの判断基準がプロンプトのバージョンによってブレやすく，再現性の面で不安がある．
* **案C（不採用）**: MySQLの全文検索（FULLTEXT INDEX）やタイトルの文字列類似度（レーベンシュタイン距離等）で判定する．
  * 利点: 追加の外部API呼び出しが一切不要で，実装・運用コストが最も低い．
  * 欠点: 表記が異なるが意味が同じ概念（「統計学の基礎」と「データのばらつきを理解する」等）を全く拾えず，実用上の検出率が低くなると想定され，クロスノートブックリンクの価値（前提知識の重複・関連の発見）を十分に発揮できないと判断し不採用とした．

### 5.5 CLI の実装言語：Go vs TypeScript vs Ruby

* **案A（採用）**: Go で実装する．
  * 利点: 単一の実行ファイルとして各OS向けに配布でき，利用者が実行環境を用意する必要がない（ReqDef 5.1）．HTTP クライアントと SSE の受信を標準ライブラリだけで書ける．
  * 欠点: フロントエンド・バックエンドと型定義を共有できず，API 仕様とのずれをコンパイル時に検出できない．
* **案B（不採用）**: TypeScript（Node.js）で実装する．
  * 利点: フロントエンドと API の型定義や API 通信層を共有できる．
  * 欠点: 利用者に Node.js が必要になり，単一の実行ファイルにするには追加のツールが要る．
* **案C（不採用）**: Ruby で実装する．
  * 利点: バックエンドと言語を揃えられる．
  * 欠点: 利用者に Ruby の実行環境が必要になる．

### 5.6 CLI の認証：トークン方式 vs Cookie セッション

* **案A（採用）**: ログイン時に発行したトークンを `Authorization: Bearer` ヘッダーで送る（4.5.4）．
  * 利点: CLI から扱いやすく，トークン単位で失効できる．DBにはハッシュのみを保存するため，DBが漏えいしてもトークンは使えない．
  * 欠点: トークン発行・失効の API と `api_tokens` テーブルが追加で必要になる．
* **案B（不採用）**: フロントエンドと同じ Cookie セッションを CLI でも使う．
  * 利点: バックエンドの認証の仕組みを1つにできる．
  * 欠点: CLI 側で Cookie と CSRF 対策を扱う必要があり，実装が複雑になる．

## 6. 懸念事項（Caveats / Security / Privacy Concerns）

* **APIキーの秘匿化**: 外部LLM APIキーは必ずバックエンド（サーバーサイド）で管理し，フロントエンドへ絶対に露出させない．環境変数またはシークレットマネージャで管理し，リポジトリへのコミットを防ぐ仕組み（lint / pre-commit hook 等）を導入する（ReqDef 5.3）．
* **学習データへの利用オプトアウト**: ユーザーの自由記述ワーク（ゴール入力・アセスメント回答等）に個人情報や機密情報が含まれる可能性があるため，LLM API呼び出し時には「モデル学習への非利用（オプトアウト）」設定を必須パラメータとし，リクエスト送信前にこの設定が有効であることをバックエンド側でバリデーションする（ReqDef 5.3）．
* **CLI のトークン管理**: CLI のトークンはユーザーの端末にファイルとして保存されるため，所有者のみ読み書きできる権限（0600）で保存し，有効期限を設ける．`campass logout` で失効でき，DBにはハッシュのみを保存する（4.5.4）．
* **プロンプトインジェクション対策**: ユーザーの自由入力がそのままLLMへのプロンプトに埋め込まれるため，システムプロンプトとユーザー入力を明確に分離し，構造化出力（JSON Schema／ツール呼び出し）を強制することで，意図しない指示の混入や出力形式の破壊を防ぐ．
* **ノートブックのデータ保持**: ノートブックおよび学習ログはユーザーが自ら削除するか退会するまで永続保持する方針のため，退会時のデータ削除フロー（物理削除 or 論理削除）を別途明確にする必要がある（ReqDef 5.4）．
* **生成コンテンツの信頼性**: LLMが生成する学習ステップの内容やリンク先には誤り・幻覚（hallucination）が含まれ得る．本バージョンでは教材コンテンツ自体の制作を対象外としているため（Non Goals），外部リンクの生存確認や内容の正確性検証は当面ユーザーの判断に委ねる旨をUI上で明示する．

## 7. テスト方針（Test Plan）

* **シラバス生成の構造検証**: LLMの出力に対し，JSON Schemaバリデーション，循環参照（DAGとして不正なエッジ）の検出，孤立ノードの検出を自動テストで行う．
* **難易度パラメータのマッピングテスト**: 「ライト／スタンダード／ディープ」それぞれの選択が，意図した `max_depth` 等のプロンプト制約に正しく変換されるかを検証する．
* **ストリーミングのE2Eテスト**: SSE接続が途中で切断された場合の再接続・再開挙動，および途中までのノードがUIに正しく反映されることを確認する．
* **クロスノートブックリンク検出ロジックのテスト**: 既知の類似・非類似タイトルのペアに対して，期待される提案／非提案の結果（4.2.7）が閾値付近でどう振れるかを検証するデータセットを用意し，回帰テストを行う．他ユーザーのノードに誤って提案されないこと，同一ペアへの重複提案が発生しないこと（UNIQUE制約）も合わせて検証する．
* **コンパス決定ロジックのテスト**: 進捗状態の異なるシラバス（未着手のみ・途中まで完了・`in_progress` が複数・サブクエストのみ完了・全完了）と，分岐・合流を含むグラフ（`supplementary` エッジ混在を含む）に対して，4.2.8 の `current_node_id` / `candidates`（内容と並び順）/ `is_goal_reached` が期待どおりになるかを検証する．
* **提案の承認／却下フローのテスト**: `PATCH /api/cross_notebook_links/:id` による状態遷移（`proposed → accepted / rejected`）が正しく行われ，却下後に同一ペアが再提案されないことを確認する．
* **セキュリティテスト**: APIキーがフロントエンドのレスポンス・ソースマップ等に含まれていないことのスキャン，オプトアウト設定が常にリクエストに付与されていることの回帰テスト．
* **CLI のテスト**: Go 標準の `testing` と `net/http/httptest` で作ったテスト用サーバーに固定の JSON を返させ，CLI 単体で検証する（実際のバックエンド・LLM API は呼ばない）．SSE 受信については，1イベントが複数の `data:` 行に分かれる場合，途中で接続が切れる場合，デコードできないイベントが来る場合を検証する．学習マップの表示については，コンパス候補が API の並びのまま表示されることを検証する．トークンファイルが 0600 で保存されることも確認する．
* **負荷テスト**: ReqDef 5.2 の想定同時接続数（通常100 DAU，ピーク1,000 DAU）を基準としたシラバス生成APIの負荷試験．

## 8. 運用・段階的リリース計画

* 初期リリースはスモールスタート仕様（通常100 DAU／ピーク1,000 DAU）のインフラ構成とし，将来的なアクセス急増時はパブリッククラウド（AWS等）でのスケールアップ／スケールアウトを前提とした設計に留める（ReqDef 5.2）．
* プロンプトテンプレートはソースコードのデプロイサイクルと切り離し，無停止でのA/Bテスト・チューニングを可能にする（ReqDef 5.4）．
* リリース初期はコア体験として F-001〜F-004, F-011 に加え，学習マップ（同一ノートブックのグラフ可視化），コンパス（F-013），クロスノートブックリンクの提案（4.2.7）も優先実装の対象とする．これは1章で確定した「学習マップとコンパスで進む」という目的そのものに直結するためである．優先度「低」の機能（F-009 既存ノード合流演出，F-010 マイルストーン成果物提示）は後続フェーズで段階的に追加する．
* クロスノートブックリンクの検出（4.2.7）はEmbedding APIコストとチューニング未了のリスクを抱えるため，初期リリース時点では類似度閾値を保守的（提案されにくい方向）に設定し，的外れな提案よりも気づきの機会を逃すことを許容する運用とする．閾値の最適化は9章のオープンな論点として運用開始後にデータドリブンで進める．

## 9. オープンな論点（今後議論が必要な事項）

* **【最優先】学習マップとクロスノートブックリンクの画面設計**: 学習マップは「同一ノートブック内のグラフをそのまま可視化したもの」，クロスノートブックリンクは「提案→承認を経て追加される他ノートブックへの接続」であるという役割分担（1〜2章）は確定した．一方で，(a) 学習マップへの具体的な遷移フロー・URL構成，(b) クロスノートブックリンクの提案をどこで（学習マップ内／通知／別画面）ユーザーに提示するか，(c) 学習マップの初回導入タイミング（オンボーディング時に見せるか等）は未確定であり，実装着手前に確定させる必要がある．
* クロスノートブックリンクの関連度判定（4.2.7）における類似度の閾値（暫定 0.80）は実データでの検証が必要．また，1つの新規ノードに対して複数の提案が生成された場合の表示上限やまとめ方も未検討．
* LLM生成コンテンツの品質担保（幻覚対策）について，将来的にファクトチェック機構やユーザーフィードバックによる品質改善ループを設けるか．
* ストリーミング中にユーザーが離脱・再訪した場合の生成状態の扱い（生成継続／破棄／再開）．CLI（4.5）で生成中に Ctrl+C で接続が切れた場合も同じ論点として合わせて決める．
* **ノード詳細の取得**: 学習マップは `summary` を含まず（4.4），ノード単体の詳細を取得する API が未定義．フロントエンドで地点を選んだときの詳細表示と，CLI の `campass show` に共通の課題．
* **フロントエンドの認証方式**: フロントエンドを Cookie セッションにするか，CLI と同じトークン方式（4.5.4，5.6）にするか．
* **CLI トークンの有効期限**: `api_tokens.expires_at` に設定する期間と，期限切れ時の扱い．
* **CLI のパスワード入力の非表示**: Go の標準ライブラリには端末のエコーを止める API がない．Unix 系では `stty` コマンドを使えるが，Windows での扱いが未決．
* **CLI の配布方法**: 実行ファイルの配布先（GitHub Releases 等）とバージョン管理．
* 前提知識アセスメント（F-004）の質問生成が，ゴールの複雑さによってはLLMのコスト・レイテンシに大きく影響する可能性があり，キャッシュ／テンプレート化の余地があるか．

## 10. 変更履歴

| バージョン | 日付 | 概要 | 変更者 |
| :--- | :--- | :--- | :--- |
| v0.1.0 | 2026/07/01 | ReqDef.md v1.0.0 をベースに新規作成 | 池田 琉俊 |
| v0.2.0 | 2026/07/04 | 星座型ビューを実装スコープに追加し，1章（目的/Non Goals），2章（背景），3章（概要），4章（データ構造・アルゴリズム・API・UI方針），5〜9章を全面的に詳細化 | 池田 琉俊 |
| v0.3.0 | 2026/07/04 | 星座型ビューの認識を修正（単一ノートブック内のグラフ可視化であり，複数ノートブック横断のクラスタ統合ではない）．他ノートブックとの関連は「提案→承認」による`cross_notebook_links`として再設計し，1〜9章の関連箇所を整合させた | 池田 琉俊 |
| v0.4.0 | 2026/10/06 | 星座型ビューを「学習マップ」に改称し，現在地から次に学ぶノードを指す「コンパス」（ReqDef F-013）を追加．用語定義，4.2.8（現在地とコンパスの決定），API（`/constellation` → `/map`，コンパス情報の返却），UI方針，テスト方針を更新 | 池田 琉俊 |
| v0.5.0 | 2026/10/06 | 一本道ビューを廃止（ReqDef F-005, F-008 廃止）．`display_order` とリニア変換（4.2.5）を廃止し，`importance_score` を `syllabus_nodes` に追加．コンパスを「必須前提を満たした未完了ノードをすべて示す」方式に変更し，現在地を進捗から決定（4.2.8）．ドリルダウンを学習マップ上に移し `GET /api/nodes/:id/children` を追加，`GET /api/notebooks/:id/syllabus` を削除．1〜9章を整合 | 池田 琉俊 |
| v0.6.0 | 2026/10/06 | 4.1.2 を DB 定義の正と明記し，`users` テーブルを追加．ER図の `assessment_targets` と 4.2.3 の `assessment_results` を `assessment_answers` に統一．フロントエンドへのストリーミング方式を SSE に統一（3.1） | 池田 琉俊 |
| v0.7.0 | 2026/10/06 | CLI クライアント（ReqDef F-014）を追加．4.5（CLI設計），`api_tokens` テーブル，トークン発行・失効 API と `GET /api/notebooks` を追加し，4.3.1 をクライアント共通の API とした．5.5・5.6 に代替案，6〜7章に CLI の懸念事項とテスト方針，9章に CLI 関連の論点を追加 | 池田 琉俊 |
| v0.8.0 | 2026/10/07 | シラバス生成 SSE のイベント形式を 4.3.1 に定義（`node` / `link_proposal` / `done` / `error`，エラーコード，終端の扱い，レスポンス例）．リンク提案を `node` から独立したイベントとし，4.3.2，4.5.3，4.5.6，4.5.7 を整合．9章から解決済みの論点を削除 | 池田 琉俊 |
