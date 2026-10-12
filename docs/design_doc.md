# Design Doc：Campass

* **ステータス**: Draft
* **著者**: 池田 琉俊
* **作成日**: 2026/07/01
* **要件定義書**: `ReqDef.md`（v1.9.0 / 2026/10/12）
* **用語集**: `GLOSSARY.md`（用語は用語集に従う）

---

## 1. 目的（Goal）

本システムの目的は，独学者が「次に何を学べばいいかわからない」「基礎学習の先が見えず挫折する」という課題を解消することである．LLM がユーザーの学習ゴールから学ぶべき内容とその順序をグラフ構造として計算し，そのグラフを (a) ゴールごとの「マップ」として地図のように俯瞰できる形で動的に提示し，(b) マップ上では「コンパス」が学習者の現在地から次に学べるノードを指し示す状態を実現する．「地図を広げ，コンパスで進む方向を確かめながら学ぶ」というのが本アプリ（Campass）のコンセプトである．加えて，(c) 複数のマップに同じ内容が出てくる場合はノードを共有し（マップ間ノード），他のマップで学んだことが今のマップでも土台になっている状態を目指す．

技術的な観点では，(1) LLM によるマップ（グラフ構造）の構造化データ生成と既存ノードの再利用，(2) マップのグラフをそのまま提示しつつ，進捗から現在地と次に学べるノードを導出するロジック，(3) ノードの内容と進捗をマップ間で共有しながら，マップごとの位置づけ（道・重要度）を分けて持つデータモデル，の3点を無理なく成立させる設計を確立することが本 Design Doc のスコープである．

### 1.1 Non Goals

* **独自LLMの学習・ファインチューニング**: 既存の外部LLM API（Claude / GPT / Gemini 等）を利用する前提とし，モデル自体の開発は行わない（ReqDef 3.2）．
* **教材コンテンツそのものの制作**: 各学習ステップの本文教材を自社で執筆・作成することは行わない．外部記事へのリンク提示とAIによる概要生成，課題提示に留める（ReqDef 3.2）．
* **詳細画面仕様・Pixel Perfect なUI定義**: 画面レイアウトの厳密な仕様はFigma等の別ドキュメントに委ね，本Docでは認知負荷軽減の設計方針までを扱う．
* **本Docでの要件の再定義**: 機能要件・非機能要件の是非そのものは ReqDef.md で確定済みという前提に立ち，本Docでは「その要件をどう実現するか」のみを議論する．

## 2. 背景（Background）

独学者は「最終的に何ができるようになりたいか（ゴール）」は漠然と持っていても，そこに至るまでの前提知識の依存関係を自力で把握することが難しく，基礎学習の途中で「これが何に繋がるのか分からない」まま離脱してしまうケースが多い（ReqDef 2.1）．また，表面的なツールの使い方（ハウツー）の習得に偏り，背後にある原理原則の理解に到達しないまま学習が止まってしまう問題もある．

これに対し，本アプリは「トップダウン逆算型ボトムアップ学習」，すなわちゴールから逆算して必要な前提知識を洗い出し，基礎から順に積み上げていく学習プロセスを LLM に計算させることで解決を図る．一方で，計算された依存関係は本質的にはグラフ（ネットワーク）構造になりやすく，そのまま提示すると学習者の認知負荷が高く「今何をすべきか」が分かりにくい．そのため，グラフ構造をそのままマップとして見せつつ，ドリルダウン（F-007）で情報量を絞り，コンパス（F-013）で「次に進める場所」を示すことで認知負荷を抑えることが本システムの中核的な設計上の論点になる．なお，当初はグラフを一本道（リニア）に変換して見せる設計（旧 F-005, F-008）であったが，v0.5.0 で廃止した．

さらに，独学者は単一のゴールだけでなく，「AIも学びたいがデザインにも興味がある」のように複数の学習ゴールを並行して抱えるケースが多い．この場合，ゴールごとに別々のグラフを作ると，同じ内容（例：統計学の基礎）を2回学ぶことになり，他のマップで既に学んだ内容が今のマップにも効いていることに気づきにくい．そこで本バージョンでは，ノードをマップではなくユーザーの持ち物とし，マップを生成するときに既存のノードをLLMに伝えて再利用させる（ADR 0003）．再利用されたノードは複数のマップに登場し，進捗はどのマップでも共通になる．一方，そのゴールの中での位置づけ（道，メインノードかどうか，重要度）はマップごとに持つため，マップを追加しても他のマップのグラフは変わらない．なお，v0.8.0 までは「他ノートブックの似たノードを Embedding で検出して提案し，承認されたらリンクする」設計であったが，v0.9.0 で廃止した．

用語は `GLOSSARY.md` を正とする．本書で特に使う用語を次に示す．

| 用語 | 定義 |
| :--- | :--- |
| マップ | ユーザーがゴールごとに持つ独立した作業スペース．ゴールに至るノードと，その間の道からなる．「地図」は比喩であり，ノードは座標を持たない（ReqDef F-012）． |
| ノード | 1つの学習項目．ユーザーの持ち物であり，複数のマップに登場できる． |
| 道 | あるノードから別のノードへの，学ぶ順番を示すつながり．おすすめの順番であり，先のノードを開始できなくするものではない． |
| メインノード | あるマップの最上位のノード．マップ画面に最初から描かれる．同じノードが，あるマップではメインノード，別のマップではサブノードになり得る．同じマップの別のメインノードの中にも現れてよい（ADR 0006）． |
| サブノード | 別のノードの内容の一部であるノード．どのマップでも同じで，ドリルダウンで見える（ReqDef F-007）． |
| 寄り道 | メインノードから出る，ゴールとの関係は薄いが興味があれば学べるテーマ．ノードではなく進捗を持たない．選ぶとそのテーマで新しいマップを作れる（ReqDef F-006）． |
| マップ間ノード | 2つ以上のマップに登場するノード．1つのノードなので，進捗はどのマップでも同じ（ReqDef F-015）． |
| 元ノード | 1つのノードでは収まらないため，そこからマップを作ったノード．そのマップでゴールに着くと，元ノードの完了を提案する（ReqDef F-017）． |
| 寄り道の出発点 | 寄り道からマップを作ったときの，寄り道が出ていたメインノード． |
| 現在地 | あるマップで学習者が今いるノード．そのマップで最後に開始または完了したノード．なければスタート地点（ノードなし）とする（4.2.8）． |
| 既知ノード | あるマップに登場するノードのうち，他のマップで学習中のもの，または完了しているもの．ある程度理解しているものとして扱う（4.2.8）． |
| コンパス候補 | 道でつながる手前のノードがすべて完了または既知ノードである，未完了のメインノード．既知ノード自体は候補にしない（4.2.8）． |
| コンパス | マップ上で，現在地からコンパス候補をすべて指し示すUI要素（ReqDef F-013）．`importance_score` の高い候補を強調し，どれに進むかはユーザーが選ぶ．候補以外のノードも開始できる． |

## 3. 概要（Overview）

本システムは，React 製フロントエンド，Ruby on Rails 製バックエンド，MySQL データベース，および外部LLM API（Claude 等）から構成される Web アプリケーションである（ReqDef 6章）．ユーザーの入力はバックエンドを経由してLLM APIへ送信され，生成されたマップのデータはストリーミング形式で逐次フロントエンドへ返却・描画される．これにより，生成に数十秒を要する処理でもユーザーは最初の一歩をすぐに読み始めることができる（ReqDef 5.2）．

システムが扱う中心的なデータは「グラフ構造を持つマップ」であり，これを (a) 道を正しく表現できるデータ構造として永続化しつつ，(b) ネットワークのままマップとして提示し，(c) 進捗から現在地とコンパス候補を導出するロジックが本システムの技術的な核となる．これに加えて，(d) ノードをユーザーの持ち物としてマップ間で共有し，マップを生成するときに既存ノードを再利用させる．共有するのはノードの内容（タイトル，概要，サブノード）と進捗であり，道・メインノードかどうか・重要度はマップごとに持つため，(b)(c) は1つのマップの範囲で計算できる．

### 3.1 ハイレベルアーキテクチャ

```
┌────────────────┐        ┌──────────────────────┐        ┌────────────────────┐
│   Frontend      │  HTTP  │   Backend             │  HTTPS │  外部LLM API         │
│   (React)       │◄──────►│   (Ruby on Rails)     │◄──────►│  (Claude / GPT等)    │
│                 │  SSE   │                        │  ストリーミング       │  ※学習に使わないプラン │
│ ・入力フォーム    │        │ ・マップ生成オーケストレーション│        └────────────────────┘
│ ・マップUI       │        │ ・プロンプトテンプレート管理  │
│ ・ドリルダウン表示 │        │ ・マップ/ノード/進捗の永続化 │
└────────────────┘        │ ・APIキーの秘匿管理        │
                            └──────────┬─────────────┘
                                       │
                                       ▼
                            ┌──────────────────────┐
                            │   MySQL                │
                            │ ・User / Map            │
                            │ ・Node / Path           │
                            │ ・Progress / Assessment │
                            └──────────────────────┘
```

* フロントエンド（React）とバックエンド（Rails）は REST API + ストリーミング（Server-Sent Events）で通信する（4.3.1）．
* バックエンドは外部LLM APIキーを一元管理し，フロントエンドへは絶対に露出させない（ReqDef 5.3）．利用者が自分のキーを設定する場合も，キーは入力して一度送られるだけで，バックエンドは暗号化して保存し，返さない（4.3.2，6章）．
* CLI（Go，ReqDef F-014）はフロントエンドと同列のクライアントとして同じ REST API + SSE を利用する．業務ロジックと外部APIキーは持たない（4.5）．
* MySQL はグラフ構造（ノード・道）を表現可能なリレーショナル設計とし，マップ（ネットワーク表示）と，マップ間でのノードの共有（ReqDef F-015）を表現する．

### 3.2 主要ユースケースフロー

ReqDef 4.2 のタイムライン形式の進行制御に対応する，代表的な一連の処理フローを示す．

1. ユーザーが学びたいことを自由入力する（F-001）．寄り道から新しいマップを作る場合は，寄り道のテーマが入力済みになる（F-006）．
2. バックエンドがLLMに「入力が具体的なゴールとして十分か」を判定させ，曖昧であれば3件のゴール候補を生成する（F-002）．ユーザーは候補から選択，または自由入力のまま次へ進む．
3. ユーザーが学習の深さ（ライト／スタンダード／ディープ）を選択する（F-003）．この選択値はLLMへのプロンプト制約（`max_depth` 等）としてそのまま渡される．
4. 難易度を選ぶとマップ画面に移り，バックエンドがLLMへマップ生成をリクエストする．プロンプトにはユーザーの既存ノードの一覧を含め，同じ内容は新しく作らずに再利用させる（F-011，F-015）．ストリーミングでノードを受信しながら，逐次DBへ永続化する．生成はリクエストから切り離したバックグラウンドジョブで行うため，ユーザーがマップ画面を離れても最後まで続く（4.2.9）．
5. 受信したノードを，フロントエンドがマップ上に順次描画する．再利用された既知ノードは最初から埋まった状態で現れ，そこから新しいノードへ道がのびる（F-009）．
6. 生成が終わるとコンパスが現れる．ユーザーはコンパス候補から次に学ぶノードを選び（F-013，4.2.8），ノードをドリルダウンしてサブノードを見たり（F-007），マイルストーンで成果物提示を行ったりしながら学習を進める（F-010）．進捗を更新すると，そのマップの現在地とコンパス候補が再計算される．
7. 興味を持った寄り道や，1つのノードでは収まらないノードからは，新しいマップを作れる（F-006，F-017）．作ったマップには，元のマップのノードや寄り道の入口から移動できる．
8. ユーザーは，LLM が作ったマップを自分で編集できる（F-018，4.2.10）．ノードの追加・外す・内容の書き換え，道とサブノードの編集，重要度の変更を行える．

## 4. 詳細設計（Detailed Design）

### 4.1 データ構造設計

マップは本質的にグラフ（有向非巡回グラフ）であり，マップ画面はこれをそのまま提示する．そのため，DB上は **ノード・道方式** のグラフ構造として保持する．ノードはユーザーの持ち物であり（ADR 0003），次のように「内容」と「マップごとの位置づけ」を分けて持つ．

* **共有するもの**: ノードの内容（`nodes`），サブノードの関係（`sub_nodes`）と，同じノードの中のサブノード間の道（`sub_node_paths`），進捗（`progress_statuses`）．
* **マップごとに持つもの**: どのノードがメインノードか（`map_nodes`），その重要度，メインノード間の道（`map_paths`），寄り道（`detours`），そのマップで行った進捗の更新の履歴（`map_progress_events`）．

並び順のような派生データは保持せず，コンパス候補は進捗と道から，現在地は進捗の履歴から，都度導出する（4.2.8）．

#### 4.1.1 ER図（論理構成）

```
users ──1:N── maps ──1:N── map_nodes ──N:1── nodes ──1:1── progress_statuses
               │  │  │          └──1:0..1── detours ──0..1:1── maps（寄り道から作ったマップ）
               │  │  ├──1:N── map_paths（同じマップのメインノード間の道）
               │  │  └──1:N── map_progress_events（このマップで行った進捗の更新の履歴）
               │  └── origin_node_id ──N:1── nodes（元ノード）
users ──1:N── nodes ──1:N── sub_nodes（ノード → サブノード）
                     └──1:N── sub_node_paths（同じノードの中のサブノード間の道）
users ──1:N── user_identities（連携した Google / GitHub のアカウント）
users ──1:N── web_sessions（ブラウザのログイン）
users ──1:N── api_tokens（CLI のトークン）
users ──1:N── cli_login_requests（CLI のログイン要求．許可されるまで user_id は NULL）
users ──1:0..1── user_llm_credentials（利用者が設定した自分の LLM API キー）
```

* `map_nodes` は「あるマップに置かれたメインノード」を表す．サブノードは `map_nodes` に置かず，`sub_nodes` によってどのマップでも同じものが見える．あるマップで `map_nodes` にあるノードはそのマップのメインノードであり，そうでなくサブノードとして見えるノードはそのマップのサブノードである．
* `map_paths` は同じマップのメインノード間の道であり，マップごとに非巡回であることを生成時に検証する（4.2.4）．道はマップごとに持つため，同じノードでもマップによって道が異なってよい．
* `sub_nodes` と `sub_node_paths` はノードの内容の一部としてマップ間で共有する．あとから作ったマップがサブノードを追加すると（4.2.4），元のマップでもドリルダウンで見えるようになる．
* `map_progress_events` は，あるマップから行った進捗の更新（開始・完了・未着手に戻す）の記録である．記録したときのメインノードの置き場所（`map_nodes`）を指し，現在地はここから導出する（4.2.8，ADR 0005）．

#### 4.1.2 テーブル定義

本節のテーブル定義を正とする（基本設計書 4章は概要のみを示し，本節を参照する）．

**`users`**

| カラム名 | 型 | 制約 | 説明 |
| :--- | :--- | :--- | :--- |
| `id` | BIGINT UNSIGNED | PK, AUTO_INCREMENT | |
| `name` | VARCHAR(255) | NOT NULL | ユーザー名．初めてログインしたときに，Google / GitHub のプロフィールの名前（なければメールアドレスの @ の前）を入れる（4.6） |
| `email` | VARCHAR(255) | NOT NULL, UNIQUE | メールアドレス．初めてログインしたときの確認済みのメールアドレス．別のアカウントを同じユーザーにまとめるときに使う（4.6） |
| `created_at` / `updated_at` | DATETIME | NOT NULL | |

パスワードは持たない（ReqDef F-019）．ログインは `user_identities` の Google / GitHub のアカウントで行う．

**`user_identities`**（ユーザーと連携した Google / GitHub のアカウント，4.6）

| カラム名 | 型 | 制約 | 説明 |
| :--- | :--- | :--- | :--- |
| `id` | BIGINT UNSIGNED | PK, AUTO_INCREMENT | |
| `user_id` | BIGINT UNSIGNED | FK → `users.id`, NOT NULL, INDEX | |
| `provider` | ENUM('google','github') | NOT NULL | |
| `provider_uid` | VARCHAR(255) | NOT NULL | Google / GitHub でのアカウントの ID．メールアドレスは変わることがあるため，ログインの判定にはこれを使う |
| `created_at` / `updated_at` | DATETIME | NOT NULL | |
| UNIQUE制約 | | `(provider, provider_uid)` | 1つのアカウントは1人のユーザーにだけ連携する |

**`web_sessions`**（ブラウザのログインのセッション，4.6）

| カラム名 | 型 | 制約 | 説明 |
| :--- | :--- | :--- | :--- |
| `id` | BIGINT UNSIGNED | PK, AUTO_INCREMENT | |
| `user_id` | BIGINT UNSIGNED | FK → `users.id`, NOT NULL, INDEX | |
| `token_digest` | CHAR(64) | NOT NULL, UNIQUE | セッショントークンの SHA-256 ハッシュ（16進）．平文は Cookie にだけ入れ，DBには保存しない |
| `user_agent` | VARCHAR(255) | NULLABLE | ログインしたブラウザの User-Agent |
| `last_used_at` | DATETIME | NOT NULL | 最後に使った時刻．書き込みは1日に1回まで（4.6） |
| `expires_at` | DATETIME | NOT NULL | 有効期限．最後に使ってから30日（4.6） |
| `created_at` / `updated_at` | DATETIME | NOT NULL | |

**`api_tokens`**（CLI 用の認証トークン，4.5.4）

| カラム名 | 型 | 制約 | 説明 |
| :--- | :--- | :--- | :--- |
| `id` | BIGINT UNSIGNED | PK, AUTO_INCREMENT | |
| `user_id` | BIGINT UNSIGNED | FK → `users.id`, NOT NULL, INDEX | |
| `token_digest` | CHAR(64) | NOT NULL, UNIQUE | トークンの SHA-256 ハッシュ（16進）．平文は発行時のレスポンスでのみ返し，DBには保存しない |
| `name` | VARCHAR(255) | NULLABLE | 発行元の識別名（例：ホスト名）．ユーザーが自分のトークンを見分けるために使う |
| `last_used_at` | DATETIME | NULLABLE | 最終利用時刻．発行後まだ使っていなければ NULL．書き込みは1日に1回まで（4.5.4） |
| `expires_at` | DATETIME | NOT NULL | 有効期限．最後に使ってから30日のスライド式で，発行時は発行時刻 + 30日．絶対的な上限はない（4.5.4） |
| `created_at` / `updated_at` | DATETIME | NOT NULL | |

**`cli_login_requests`**（CLI のログイン要求．ブラウザで許可されるのを待つ，4.5.4）

| カラム名 | 型 | 制約 | 説明 |
| :--- | :--- | :--- | :--- |
| `id` | BIGINT UNSIGNED | PK, AUTO_INCREMENT | |
| `device_code_digest` | CHAR(64) | NOT NULL, UNIQUE | `device_code` の SHA-256 ハッシュ（16進）．平文は作成時のレスポンスでのみ返し，DBには保存しない |
| `user_code` | CHAR(9) | NOT NULL, UNIQUE | 利用者がブラウザに打つコード（`XXXX-XXXX`）．使い捨てで，同じ値を二度使わない |
| `name` | VARCHAR(255) | NULLABLE | CLI のマシン名．S-04 の確認に出し，発行するトークンの `api_tokens.name` にする |
| `user_id` | BIGINT UNSIGNED | FK → `users.id`, NULLABLE, INDEX | 許可したユーザー．許可されるまで NULL |
| `status` | ENUM('pending','approved','denied','consumed') | NOT NULL, DEFAULT 'pending' | `consumed` はトークンを CLI に渡し終えた状態 |
| `last_polled_at` | DATETIME | NULLABLE | CLI が最後にトークンを受け取りに来た時刻．間隔より早い受け取りを `slow_down` にするために使う |
| `expires_at` | DATETIME | NOT NULL | 有効期限．作成から10分 |
| `created_at` / `updated_at` | DATETIME | NOT NULL | `created_at` はログインを始めた時刻として S-04 に出す |

**`user_llm_credentials`**（利用者が設定した自分の LLM API キー，ReqDef F-020，4.3.2）

| カラム名 | 型 | 制約 | 説明 |
| :--- | :--- | :--- | :--- |
| `id` | BIGINT UNSIGNED | PK, AUTO_INCREMENT | |
| `user_id` | BIGINT UNSIGNED | FK → `users.id`, NOT NULL, UNIQUE | 1人1つ．入力し直すと同じ行を書き換える |
| `provider` | VARCHAR(32) | NOT NULL | 会社（今は `gemini`）．実装済みの会社だけを受け付ける（アプリケーション層で候補の設定ファイルと照らす．4.3.1）．会社を足すたびに DB を変えずに済むよう ENUM にしない |
| `model` | VARCHAR(255) | NOT NULL | モデル．その会社の候補（設定ファイル）にあるものだけを受け付ける |
| `api_key` | TEXT | NOT NULL | API キー．Active Record Encryption で暗号化して保存する（6章）．暗号文は平文より長くなるため TEXT とする．どの API の応答にも含めない |
| `api_key_last4` | CHAR(4) | NOT NULL | キーの末尾4文字．S-06 でどのキーを設定したかを見分けるために平文で持つ |
| `verified_at` | DATETIME | NOT NULL | 保存の前にキーとモデルを確かめた日時（4.3.2） |
| `created_at` / `updated_at` | DATETIME | NOT NULL | |

* 行がない利用者はサービスのキーを使う．削除（`DELETE /api/llm_credential`）は行を消す（4.3.1）．

**`maps`**

| カラム名 | 型 | 制約 | 説明 |
| :--- | :--- | :--- | :--- |
| `id` | BIGINT UNSIGNED | PK, AUTO_INCREMENT | |
| `user_id` | BIGINT UNSIGNED | FK → `users.id`, NOT NULL, INDEX | |
| `title` | VARCHAR(255) | NOT NULL | マップの表示名（LLM提案 or ユーザー編集） |
| `goal_text` | TEXT | NOT NULL | ユーザーが入力・確定した学習ゴールの原文 |
| `difficulty` | ENUM('light','standard','deep') | NOT NULL | F-003 の難易度選択値．生成のやり直しと，後のフェーズの F-016 で深さの目安に使う |
| `status` | ENUM('generating','ready','failed') | NOT NULL, DEFAULT 'generating' | マップ生成の進行状態（4.2.9） |
| `generation_error_code` | ENUM('parse_failed','invalid_map','llm_api_error','user_api_key_invalid','user_api_key_quota_exceeded','internal_error','timed_out') | NULLABLE | `failed` になった理由．`error` イベントの `code`（4.3.1）と同じ値．利用者向けの文言は保存せず，応答時にコードから作る |
| `generation_heartbeat_at` | DATETIME | NULLABLE | 生成ジョブが最後にノードを保存した時刻．ジョブが消えたことの検知に使う（4.2.9） |
| `origin_node_id` | BIGINT UNSIGNED | FK → `nodes.id`, NULLABLE, UNIQUE, ON DELETE SET NULL | 元ノード（F-017）．UNIQUE により，1つのノードから作れるマップは1つだけ |
| `created_at` / `updated_at` | DATETIME | NOT NULL | `updated_at` は，このマップから変更を加えたときに更新する（下の注記）．マップ一覧の並び順と，最新のマップへの転送に使う（4.3.1，4.4） |

`maps.updated_at` を更新するのは，このマップに副作用を与えた次のときである．`maps` の行の変更（Rails が自動で更新する）に加え，`maps` の行が変わらない変更でも明示的に更新する．

* 生成：ノードの保存（4.2.9）と，`status` の変更（`ready`，`failed`．`timed_out` を含む）．
* 進捗：このマップからの進捗の更新（`map_progress_events` への記録．4.2.8）．
* 編集：このマップからの編集（4.2.10）．メインノード・道・重要度の変更と，`map_id` にこのマップを指定した共有の編集（内容，サブノード，サブノード間の道）．

読むだけの操作では更新しない．また，共有のノード（ノードの内容，サブノード，サブノード間の道，進捗）が他のマップからの操作で変わっても，そのノードが登場するマップの `updated_at` は更新しない．更新するのは操作したマップだけで，開いていないマップが最新になることはない．たとえば次の場合，他のマップは最新にならない．

* 他のマップから，共有のノードの内容・サブノード・サブノード間の道を編集した．
* 他のマップから，共有のノードの進捗を更新した．
* 他のマップの生成で，既存ノードを再利用してサブノードを足した（4.2.4）．
* 元ノードから作ったマップでメインノードを置いた・外したため，元ノードのサブノードが変わった（4.2.10）．元ノードがあるマップは最新にならない．
* 他のマップを削除し，どこからも参照されなくなったノードが消えた．

実装では，共有のテーブル（`nodes`，`sub_nodes`，`sub_node_paths`，`progress_statuses`）の変更から `maps` へ更新を伝えない（Rails の `touch: true` で関連するマップをまとめて更新しない）．操作したマップ（API の `mapId` / `map_id`，生成中のマップ）の `updated_at` だけを明示的に更新する．

寄り道から作ったマップは `detours.spawned_map_id` から参照する．`origin_node_id` を持つマップが同時に寄り道から作ったマップになることはない（アプリケーション層で検証する）．

**`nodes`**（ノードの内容．ユーザーの持ち物）

| カラム名 | 型 | 制約 | 説明 |
| :--- | :--- | :--- | :--- |
| `id` | BIGINT UNSIGNED | PK, AUTO_INCREMENT | |
| `user_id` | BIGINT UNSIGNED | FK → `users.id`, NOT NULL, INDEX | ノードはユーザー単位で共有する（他ユーザーとは共有しない） |
| `title` | VARCHAR(255) | NOT NULL | |
| `summary` | TEXT | NOT NULL | 概要文．LLM が作ったノードでは AI による概要（F-011），ユーザーが作ったノードでは任意入力で空文字を許す（F-018） |
| `created_at` / `updated_at` | DATETIME | NOT NULL | |

**`map_nodes`**（マップに置かれたメインノード）

| カラム名 | 型 | 制約 | 説明 |
| :--- | :--- | :--- | :--- |
| `id` | BIGINT UNSIGNED | PK, AUTO_INCREMENT | |
| `map_id` | BIGINT UNSIGNED | FK → `maps.id`, NOT NULL, ON DELETE CASCADE | |
| `node_id` | BIGINT UNSIGNED | FK → `nodes.id`, NOT NULL, INDEX | |
| `importance_score` | FLOAT | NOT NULL, DEFAULT 0 | このゴールの中での重要度（0〜1）．LLM が付与し，ユーザーは高・中・低の3段階で変更できる（4.2.10）．コンパス候補の強調順に使う（4.2.8） |
| `created_at` / `updated_at` | DATETIME | NOT NULL | |
| UNIQUE制約 | | `(map_id, node_id)` | |

**`map_paths`**（マップごとのメインノード間の道）

| カラム名 | 型 | 制約 | 説明 |
| :--- | :--- | :--- | :--- |
| `id` | BIGINT UNSIGNED | PK, AUTO_INCREMENT | |
| `map_id` | BIGINT UNSIGNED | FK → `maps.id`, NOT NULL, ON DELETE CASCADE | |
| `from_node_id` | BIGINT UNSIGNED | FK → `nodes.id`, NOT NULL, INDEX | 道の元（先に学ぶノード）．同じマップの `map_nodes` にあること |
| `to_node_id` | BIGINT UNSIGNED | FK → `nodes.id`, NOT NULL, INDEX | 道の先．同じマップの `map_nodes` にあること |
| UNIQUE制約 | | `(map_id, from_node_id, to_node_id)` | 同一方向の重複を禁止 |

**`sub_nodes`**（サブノードの関係．マップ間で共有）

| カラム名 | 型 | 制約 | 説明 |
| :--- | :--- | :--- | :--- |
| `id` | BIGINT UNSIGNED | PK, AUTO_INCREMENT | |
| `node_id` | BIGINT UNSIGNED | FK → `nodes.id`, NOT NULL, INDEX | サブノードを持つノード |
| `sub_node_id` | BIGINT UNSIGNED | FK → `nodes.id`, NOT NULL, INDEX | サブノード |
| UNIQUE制約 | | `(node_id, sub_node_id)` | |

**`sub_node_paths`**（同じノードの中のサブノード間の道．マップ間で共有）

| カラム名 | 型 | 制約 | 説明 |
| :--- | :--- | :--- | :--- |
| `id` | BIGINT UNSIGNED | PK, AUTO_INCREMENT | |
| `node_id` | BIGINT UNSIGNED | FK → `nodes.id`, NOT NULL, INDEX | どのノードの中の道か |
| `from_node_id` | BIGINT UNSIGNED | FK → `nodes.id`, NOT NULL | 道の元．`node_id` のサブノードであること |
| `to_node_id` | BIGINT UNSIGNED | FK → `nodes.id`, NOT NULL | 道の先．`node_id` のサブノードであること |
| UNIQUE制約 | | `(node_id, from_node_id, to_node_id)` | |

**`detours`**（寄り道）

| カラム名 | 型 | 制約 | 説明 |
| :--- | :--- | :--- | :--- |
| `id` | BIGINT UNSIGNED | PK, AUTO_INCREMENT | |
| `map_node_id` | BIGINT UNSIGNED | FK → `map_nodes.id`, NOT NULL, UNIQUE, ON DELETE CASCADE | 寄り道が出ているメインノード．UNIQUE により1つのメインノードにつき最大1つ（F-006） |
| `title` | VARCHAR(255) | NOT NULL | 寄り道のテーマ |
| `reason` | TEXT | NOT NULL | ゴールとの関係（ノードの詳細に表示する） |
| `spawned_map_id` | BIGINT UNSIGNED | FK → `maps.id`, NULLABLE, UNIQUE, ON DELETE SET NULL | この寄り道から作ったマップ．NULL の間はノードの詳細にだけ表示し，作成後はマップ画面に行き止まりの入口として描く |
| `created_at` / `updated_at` | DATETIME | NOT NULL | |

**`progress_statuses`**（進捗．マップ間で共有）

| カラム名 | 型 | 制約 | 説明 |
| :--- | :--- | :--- | :--- |
| `id` | BIGINT UNSIGNED | PK, AUTO_INCREMENT | |
| `node_id` | BIGINT UNSIGNED | FK → `nodes.id`, NOT NULL, UNIQUE | 1ノード1レコード．どのマップでも同じ進捗 |
| `status` | ENUM('not_started','in_progress','completed') | NOT NULL, DEFAULT 'not_started' | |
| `started_map_id` | BIGINT UNSIGNED | FK → `maps.id`, NULLABLE, ON DELETE SET NULL | 学習中にしたマップ．既知ノードの判定に使う（4.2.8）．NULL の学習中ノードは，どのマップでも「そのマップで始めた」ものとして扱う |
| `milestone_artifact_url` | VARCHAR(2048) | NULLABLE | F-010 のマイルストーン成果物リンク |
| `completed_at` | DATETIME | NULLABLE | |
| `created_at` / `updated_at` | DATETIME | NOT NULL | |

**`map_progress_events`**（マップごとの進捗の更新の履歴．現在地の導出に使う．ADR 0005）

| カラム名 | 型 | 制約 | 説明 |
| :--- | :--- | :--- | :--- |
| `id` | BIGINT UNSIGNED | PK, AUTO_INCREMENT | 記録の順番にも使う |
| `map_id` | BIGINT UNSIGNED | FK → `maps.id`, NOT NULL, ON DELETE CASCADE | 進捗を更新したマップ |
| `map_node_id` | BIGINT UNSIGNED | FK → `map_nodes.id`, NULLABLE, ON DELETE SET NULL, INDEX | 記録したときのメインノードの置き場所．マップから外すと NULL になり，現在地の計算に使わなくなる．置き直しても新しい置き場所の行になるため，古い記録は戻らない |
| `node_id` | BIGINT UNSIGNED | FK → `nodes.id`, NOT NULL, ON DELETE CASCADE | 進捗を更新したノード．外した後も，将来の履歴表示でどのノードの記録か分かるように持つ |
| `event` | ENUM('started','completed','reset') | NOT NULL | 開始・完了・未着手に戻した |
| `created_at` | DATETIME | NOT NULL | 追記のみで更新しないため `updated_at` は持たない |
| INDEX | | `(map_id, id)` | |

* `map_paths`，`sub_node_paths`，`sub_nodes` はDBレベルでは循環を防止できないため，4.2.4 の生成時バリデーションと 4.2.10 の編集時の検証で非巡回性を保証する．
* マップを削除すると，`map_nodes`，`map_paths`，`detours`，`map_progress_events` は連鎖削除される．ノードは，どのマップの `map_nodes` にも，どのノードの `sub_nodes` にも残らなくなった場合に，アプリケーション層で削除する（サブノードも同じ規則で辿って削除する）．他のマップに登場するノードとその進捗は残す．
* 生成中（`generating`）のマップも削除できる．途中まで保存したノードは，上の規則で `ready` のマップと同じように扱う．削除と生成ジョブのノード保存はどちらも最初に `maps` の行をロックし，同時に起きても順番に処理する（4.2.9）．
* マップを削除する前に，そのマップで学習中にしたノード（`started_map_id` がそのマップ）を利用者に知らせる（4.3.1 の `GET /api/maps/:id/deletion_preview`）．削除後，それらのノードは他のマップで「そのマップで始めた」学習中ノードとして扱われ，既知ノードにはならない．
* メインノードをマップから外したときや，サブノードをノードから外したとき（F-018）も，どこにも残らなくなったノードは同じ規則で削除する（4.2.10）．

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

「ライト／スタンダード／ディープ」の選択値を，マップ生成プロンプトの `max_depth`（ドリルダウン階層数），`node_count_target`（メインノード数の範囲），サブノード数の目安という3つのパラメータにマッピングする．マッピング値はソースコードから切り離し，4.3.2 で述べるプロンプトテンプレート管理の対象とする．寄り道は難易度に関係なく，1つのメインノードにつき最大1つ（勧める価値がある場合のみ）とする（F-006）．

初期値の目安（プロンプトテンプレート側の設定ファイルで管理する想定値）:

| 難易度 | `max_depth` | `node_count_target`（メインノード） | サブノード数の目安 |
| :--- | :--- | :--- | :--- |
| ライト | 1（ドリルダウンなし相当） | 5〜8 | なし |
| スタンダード | 2 | 8〜15 | 各メインノードに2〜3個 |
| ディープ | 3 | 15〜25 | 各メインノードに3〜4個．`importance_score` が0.8以上のメインノードは，サブノードの中身（3階層目）も書く |

* **`node_count_target` は範囲**: プロンプトでは「メインノードを必ず N 個以上 M 個以下にする」と指示し，範囲外の出力は検証エラーとする（4.2.4）．プロトタイプでは「目安」として伝えると，ディープでも15個を下回った．
* **サブノード数の目安**: `max_depth` は入れ子の上限にすぎず，それだけではディープでもサブノードがほとんどできなかったため，目安を指示する．目安は検証しない．

```
function buildGenerationParams(difficulty):
    config = loadPromptConfig("difficulty_mapping")  # 外部設定ファイルから取得
    return config[difficulty]
    # => { max_depth, node_count_target（範囲）, サブノード数の目安 }
```

#### 4.2.3 前提知識アセスメント（廃止）

v0.10.0 で前提知識アセスメントを廃止したため（ReqDef F-004），質問の生成・回答の保存（`assessment_questions` / `assessment_answers`）と，既習スキップ推奨（`map_nodes.skip_recommended`）は廃止した．必須の機能ではなく，初期入力の手順が増えるためである．

#### 4.2.4 マップの動的生成（F-011，F-015）

LLMへは，ゴール・難易度パラメータに加え，**ユーザーの既存ノードの一覧**（ID，タイトル，そのノードのサブノードの ID）を含むプロンプトを送信する．LLMは同じ内容のノードを新しく作らず，既存ノードの ID を指定して再利用する（ADR 0003）．既存ノードは完了しているかどうかに関係なく再利用の対象とする．出力はJSON Schema による構造化出力（またはツール呼び出し形式）で形式を強制し，パース失敗時のリトライ（最大2回）をバックエンド側に実装する．

この節の規則は，Gemini を直接呼ぶプロトタイプ（ブランチ `prototype/llm-map-generation`．main にはマージしない）で確かめた結果を反映している．下の「構造化出力に特有の点」以外は，今の構造化出力の方式でも，ツール呼び出しでノードを組み立てる方式（#26 で検討中）でも使う．

LLM の出力は，メインノードの配列とし，各メインノードは次の項目を持つ．

| 項目 | 説明 |
| :--- | :--- |
| `ref` | 出力内での仮 ID．道やサブノードの参照に使う |
| `existing_node_id` | 既存ノードを再利用する場合のノード ID．新規の場合は `null` |
| `title` / `summary` | 新規ノードの場合のみ使う |
| `from` | このマップでこのノードへ道がのびてくるメインノードの `ref` の配列．「知らないと理解できない前提」だけを表す．並行して学べるノードは並べ，一列につなげない（プロンプトで指示する．「先に学ぶと良い」と書くと，前提関係の薄いノードまで一列につながった） |
| `importance_score` | このゴールの中での重要度（0〜1） |
| `sub_nodes` | サブノードの配列．各要素はメインノードと同じく `ref`，`existing_node_id`，`title`，`summary`，`from`（同じノードの中のサブノードの `ref`），`sub_nodes` を持つ（`max_depth` まで入れ子） |
| `detour` | 寄り道（`title`，`reason`）．勧める価値がない場合は `null`（F-006） |

* **再利用したノードのサブノード**: 再利用したノードの既存のサブノードは，生成で消さずに残す．LLM は再利用したノードについても，既存のサブノードを含めて中身全体を `sub_nodes` に書いてよい（既存のサブノードは `existing_node_id` で指す．プロトタイプでは，再利用したノードの既存のサブノードを書き直してくることがあったため，許すことにした）．保存のときは次のようにする．
  * すでにある包含関係（`sub_nodes`）とサブノード間の道（`sub_node_paths`）は無視し，重複させない．新しいものだけを足す．
  * 出力に書かれなかった既存のサブノードや道は消さない．そのノードは他のマップで学習中のことがあるため，生成で中身を減らさない．
  * 足した道で `sub_node_paths` が循環したら，検証エラーとする（下のバリデーション）．

  追加したサブノードは `sub_nodes` に保存され，そのノードが登場する他のマップでもドリルダウンで見えるようになる（ADR 0003）．既存のサブノードと重複しないよう，再利用候補のノードについてはサブノードも一覧に含めて渡す．
* **元ノードからのマップ（F-017）**: 元ノード X からマップを作る場合，X の既存のサブノードを優先して再利用させる．生成したメインノードのうち X のサブノードでないものは，X のサブノードとしても `sub_nodes` に追加する．これにより「元ノードから作ったマップのノードは，元ノードのサブノード」という関係（GLOSSARY.md）がデータ上も成り立つ．
* **ゴール**: 生成の検証では，出力の最後のメインノードをゴールのノードとみなす．どのメインノードも，道をたどってそのノードへ行けなければならない（ゴールへつながらないノードを作らないよう，プロンプトでも指示する）．プロトタイプでは，ゴールに関係のないノード（例：Git）が孤立してできた．この見なしは生成時の検証だけに使い，順番やゴールのノードは保存しない（ゴール到達は 4.2.8 のとおりすべてのメインノードの完了で決める）．
* **分岐の形**: 3つ以上に分かれる形を無理に作らせない．Gemini は「並べて学べる」ことを，分岐ではなく `from` が空のメインノードを増やすことで表した．
* **サブノードと道の区別**: 「あるノードを，そのノード自身のサブノードへ道で結ぶ」ような出力は，内容の一部を順番の関係として書いた誤りであるため，プロンプトで避けるよう指示する．ただし検証エラーにはしない（誤っても，完了をユーザーが決めるため学習は止まらない．4.2.8）．同じマップでメインノードが別のメインノードの中にも現れること自体は許す（ADR 0006）．
* **バリデーション**: 次のいずれかに当てはまる出力は検証エラーとし，再生成させる（最大2回）．該当する道やサブノードを黙って除去・修正しない．
  * このマップの `map_paths` が循環する．
  * あるノードの中の `sub_node_paths` が循環する．
  * `sub_nodes` が循環する（例：X が Y のサブノードであり，Y が X のサブノードでもある）．既存ノードの再利用によって起こり得る．
  * 未知の `ref` や，ユーザーの持ち物でない `existing_node_id` を参照している．
  * ゴールへ道をたどって行けないメインノードがある．
  * メインノードの数が `node_count_target` の範囲（4.2.2）の外にある．
* **構造化出力に特有の点**: 今の方式（JSON Schema による構造化出力）でだけ当てはまる点を次に示す．
  * スキーマは，`sub_nodes` を `max_depth` まで入れ子に展開した形で渡す（Gemini の `responseJsonSchema`）．
  * 件数（メインノード数・サブノード数）は，JSON Schema の `minItems` / `maxItems` では強制しない．Gemini では，入れ子が深いほど，件数の値が大きいほど，スキーマが `400 INVALID_ARGUMENT` で拒否され，スタンダード以上で使えなかったためである（Gemini に特有の点）．件数はプロンプトで指示し，メインノード数だけを上のバリデーションで確かめる．
  * 再生成（最大2回）では，前回の出力と検証エラーを会話の続きとして渡す．同じプロンプトで作り直すと，同じ誤りを繰り返したためである（3回とも同じ孤立ノードが出た）．ただし，ノード単位で保存・送信したあとの再生成は 4.2.9（同じマップでのやり直しをしない）とぶつかるため，いつ再生成できるかは 9章の論点とする．
* **プロンプト長**: 既存ノードの一覧は，まずユーザーの全ノードを渡す．ノード数が増えてプロンプトが長くなりすぎた場合の絞り込み方法は 9章の論点とする．

#### 4.2.5 リニア（一本道）変換アルゴリズム（廃止）

v0.5.0 で一本道ビューを廃止したため，本アルゴリズム（トポロジカルソートによる `display_order` の確定）は廃止した（ReqDef F-005, F-008）．学習の進め方は 4.2.8 のコンパスで示す．

#### 4.2.6 ドリルダウン展開（F-007）

マップの初期表示ではメインノード（`map_nodes`）のみを描画し，ユーザーがノードを選んだ際に，そのサブノード群とその間の道を `GET /api/nodes/:id/sub_nodes`（4.3.1）で取得し，そのノードの内部として展開する．サブノード群もマップと同じくグラフのまま表示する．サブノードはマップ間で共有されるため，どのマップから開いても同じ結果になる．元ノード（そこから作ったマップがあるノード）を選んだ場合は，ドリルダウンの代わりにそのマップへ移動する（F-017）．

#### 4.2.7 クロスノートブックリンク：即時提案処理（廃止）

v0.9.0 でノードをマップ間で共有する方式（4.2.4，ADR 0003）に変えたため，Embedding 類似度による関連ノードの検出と提案・承認の処理は廃止した．`cross_notebook_links` テーブルとノードの `embedding` も削除した．

#### 4.2.8 現在地とコンパスの決定（F-013）

コンパスは「マップ上の現在地から，今進める場所（コンパス候補）をすべて指す」ものであり，順序情報や座標は持たない．コンパス候補は，そのマップの `map_paths` と共有の `progress_statuses` から都度導出する．対象はそのマップのメインノード（`map_nodes`）とする．現在地は，そのマップの進捗の更新の履歴（`map_progress_events`）から導出する（ADR 0005）．

```
function resolveCompass(mapId):
    map   = loadMap(mapId)
    nodes = loadMainNodes(mapId)  # map_nodes

    # 既知ノード: 他のマップで学習中のもの（完了済みは別に扱う）
    # started_map_id が NULL の学習中ノードは「このマップで始めた」ものとみなす
    knownInProgress(n) = n.progress.status == "in_progress"
                         and n.progress.started_map_id != null
                         and n.progress.started_map_id != mapId
    satisfied(n) = n.progress.status == "completed" or knownInProgress(n)

    # コンパス候補: 未完了で既知ノードでなく，道でつながる手前のノードがすべて満たされている
    candidates = nodes where node.progress.status != "completed"
                     and not knownInProgress(node)
                     and all(satisfied(from) for from in pathSources(mapId, node))

    currentNodeId = resolveCurrentNode(mapId)

    # メインノードが0個のマップは，「すべて完了」を中身なしに満たしてもゴール到達にしない
    if nodes.empty:
        return { currentNodeId: null, candidates: [], isGoalReached: false }

    if all(node.progress.status == "completed" for node in nodes):
        return { currentNodeId: currentNodeId, candidates: [], isGoalReached: true }

    # 強調表示のため importance_score の高い順，同点は id 順で並べる
    sortBy(candidates, -node.importanceScore, node.id)
    return { currentNodeId: currentNodeId, candidates: candidates, isGoalReached: false }

function resolveCurrentNode(mapId):
    # 外したメインノードの記録は map_node_id が NULL になっているので使わない
    events = map_progress_events where map_id == mapId and map_node_id != null

    # 置き場所ごとに最新の記録だけを見る．未着手に戻したものは現在地にしない
    latest = for each map_node_id in events: the event with the largest id
    active = latest where event.event in ("started", "completed")

    # 最も新しい開始・完了の記録のノード．なければスタート地点
    return active.max_by(id)?.node_id or null
```

* **既知ノード**: あるマップに登場するノードのうち，他のマップで学習中または完了のもの．完了したノードはどのマップで完了したかに関係なく，候補にならず，道の手前としても満たしたものとして扱う．学習中のノードは，`started_map_id` が今のマップでなければ既知ノードとして候補から外し，道の手前としては満たしたものとして扱う．今のマップで学習中にしたノードは，今まさに取り組んでいるものとして候補に含める．
* 候補が複数ある場合はすべてを示し，どれに進むかはユーザーが選ぶ．`importance_score` は強調表示のためだけに使い，候補の絞り込みには使わない．
* **コンパスは案内であり，制限ではない**: 候補でないノードも，ユーザーが選べば開始できる．未完了のメインノードがすべて他のマップで学習中の場合など，ゴール未達でも候補が空になることがある．
* **ゴール到達**: そのマップのメインノードが1つ以上あり，すべて完了したとき．完了はいつもユーザーが決め，システムが自動で完了にすることはない．マップに元ノードがある場合，ゴール到達時に元ノードの完了を提案する（`PATCH` のレスポンスの `origin_completion_suggestion`，4.3.1）．ゴール到達後にメインノードを追加すると未到達に戻るが（4.2.10），完了にした元ノードの進捗は変えない．
* **空のマップ**: メインノードをすべて外したマップ（4.2.10）は，ゴール到達ではなく，候補も空とする．
* **現在地の更新**: `PATCH /api/maps/:mapId/nodes/:nodeId/progress` で，そのマップのメインノードを開始・完了・未着手に戻したとき，`map_progress_events` にそのマップの記録（`started` / `completed` / `reset`）を追加する．現在地は `resolveCurrentNode` で導出し直す．サブノードの進捗の更新や，他のマップでの更新では記録しないため，このマップの現在地は動かない．ノードを学習中にしたときは `progress_statuses.started_map_id` に `mapId` を記録し，未着手に戻したときは NULL に戻す．
* **現在地が戻る場合**: 現在地のノードを未着手に戻したり，マップから外したりすると（4.2.10），その前に開始・完了したノードが現在地になる．記録は消さずに残し，将来の履歴表示に使えるようにする（ADR 0005）．
* サブノードの進捗も記録できるが，現在地・コンパス候補・ゴール到達の判定には使わない．
* 現在地・候補はバックエンドで決定し，フロントエンドでは再計算しない．進捗更新のたびに再計算し，レスポンスに最新のコンパス情報を含める．

#### 4.2.9 生成ジョブと接続の切断（F-011）

マップ生成は，クライアントとの SSE 接続から切り離したバックグラウンドジョブで行う（ADR 0004）．Web でページを離れたり再読み込みしたりしても，CLI で Ctrl+C を押しても，バックエンドからはどちらも「SSE 接続が切れた」としか見えないため同じ扱いとし，生成は最後まで続ける．

* **ジョブの実行方式**: ActiveJob の `:async` アダプタ（Rails 標準．Web サーバーのプロセス内のスレッドプール）で動かし，gem もプロセスも増やさない．プロセスの再起動・デプロイでジョブは消えるが，下のハートビートで `failed` として検知する．比較した方式は 5.10 に示す．
* **DB を唯一の正とする**: ジョブは 4.2.4 のとおりノードを1つずつ検証して DB に保存するだけで，クライアントへは送らない．SSE（4.3.1 の `GET /api/maps/:id/generation`）は DB から保存済みのノードを読んで送る．これにより，保存したノードと送ったノードは常に一致し，途中で失敗したときのロールバックが不要になる（5.2）．
* **ノードの保存**: ノード1つ分（`nodes`，`map_nodes`，`map_paths`，`sub_nodes`，`sub_node_paths`，`detours`）を1つのトランザクションで保存する．トランザクションの最初に `maps` の行を `SELECT … FOR UPDATE` でロックし，次のどちらかならノードを保存せずに LLM のストリームを閉じて終了する．
  * マップが削除されていた：ログに記録して静かに終える（`failed` にはしない）．
  * `status` が `generating` でなくなっていた：ハートビート切れで `failed` にされた後に，遅れていたジョブが書き込むのを防ぐ．
  
  保存したら `maps.generation_heartbeat_at` を現在時刻に更新する．マップの削除（4.1.2）も同じ行を先にロックするため，ノード1つ分の書き込みは全部入るか全部入らないかのどちらかになる．
* **失敗の検知（2段構え）**:
  1. ジョブの中で例外が起きたら，`rescue` / `ensure` で `maps.status = failed` と `generation_error_code` を保存する．例外の詳細はサーバーログにだけ出す．
  2. プロセスごと消えた場合，ジョブは何も書けない．そこで，`generating` のまま `generation_heartbeat_at` から一定時間（初期値5分．運用で調整する）経ったマップを，ジョブが消えたものとみなして `failed`（`timed_out`）にする．この判定は，SSE のループと，マップを読む API（`GET /api/maps`，`GET /api/maps/:id`）が呼ばれたときに行う．
* **使う LLM のキー（ReqDef F-020）**: ジョブは始まったときに一度だけ利用者の `user_llm_credentials` を読み（なければサービスのキー），その会社・モデル・キーで LLM のクライアントを作って最後まで使い続ける（4.3.2）．生成の途中で利用者がキーを変えたり消したりしても，その生成には影響しない．キーの平文はジョブの引数に入れず，ジョブにはマップだけを渡す．ActiveJob は引数をシリアライズし，既定でログに出すためである．
* **完了**: 全ノードを保存したら `status = ready` にする．コンパスは `ready` になってから返す（生成の途中では候補が後から変わるため）．
* **失敗したマップ**: 保存済みのノードはそのまま見られるが，コンパスは出さない．生成のやり直しや再開は行わず，削除して作り直すことを案内する．LLM のストリームは途中から再開できず，同じマップでやり直すと最初から生成し直すことになり，すでに保存して送ったノードと食い違うためである．既存ノードの再利用（4.2.4）により，始めたノードの進捗は新しいマップに引き継がれる．
* **生成の中止はない**: マップを残したまま生成だけを止める操作は設けない．不要になったマップは，生成中でも削除できる（4.1.2）．

#### 4.2.10 ノードの編集（F-018）

LLM が作ったマップを，ユーザーが Web と CLI（4.5.7）から編集できるようにする．業務ロジック（検証，後始末，確認が必要かの判定）はすべてバックエンドが持ち，クライアントは結果を表示するだけとする．

**操作と影響範囲**

| 操作 | 影響範囲 | 内容 |
| :--- | :--- | :--- |
| ノードの内容の編集 | 全マップ | タイトルと概要を書き換える．ノードは共有なので，そのノードが登場するすべてのマップに反映される．共有の解除はしない（9章） |
| メインノードの追加 | このマップ | 新しいノードを作って置くか，自分の既存ノードを置く．新しいノードの概要は任意入力（空文字を許す） |
| メインノードを外す | このマップ | ノードそのものではなく，このマップでの置き場所（`map_nodes`）を消す．最後の1つも外せる |
| 道の追加・削除 | このマップ | `map_paths` を追加・削除する |
| サブノードの追加・外す | 全マップ | `sub_nodes` を追加・削除する．追加は新しく作るか既存ノードを選ぶ |
| サブノード間の道の追加・削除 | 全マップ | `sub_node_paths` を追加・削除する |
| 重要度の変更 | このマップ | 高・中・低を選ぶ．`importance_score` には 0.9 / 0.5 / 0.1 を保存する |

寄り道の追加・編集・削除と，ノードを全マップから一度に消す操作は設けない．どこにも残らなくなったノードは，下の後始末で自動的に削除する．

**編集できるマップ**

* 編集は `ready` のマップでだけ行える．`generating` のマップでは生成ジョブがノードを保存している途中であり，`failed` のマップは削除して作り直す方針のためである（4.2.9）．
* 全マップに反映される操作（内容，サブノード，サブノード間の道）も，どのマップから操作したか（`map_id`）を受け取り，そのマップが `ready` であることを確かめる．
* マップに関わる操作は，生成ジョブ・マップの削除と同じく，最初に `maps` の行を `SELECT … FOR UPDATE` でロックする（4.2.9）．

**既存ノードの提案**

* メインノードやサブノードを追加するとき，入力中のタイトルに部分一致する自分のノードを提案する（`GET /api/nodes?q=`）．他ユーザーのノードは含めない．
* 選べば既存ノードを置き，選ばなければ新しく作る．LLM や Embedding は使わない．提案は利用者が見て選ぶため，判定が粗くても誤った再利用にはならない．
* すでにこのマップのメインノードであるノードは，選べない状態で示す（`map_nodes` は同じマップに同じノードを2回置けない）．このマップの別のメインノードの中にあるノードは選べるが，「『A』の中にもあります」と示し，そのノードへ道をつなぐ選択肢に気づけるようにする（ADR 0006）．

**検証**

* 次の編集は保存せず，`422` とエラーコード `cycle` を返す．応答には循環するノードの並び（例：A → B → A）を含める．該当する道やサブノードを黙って除去・修正しない．
  * このマップの `map_paths` が循環する道の追加（自分自身への道も含む）．
  * あるノードの中の `sub_node_paths` が循環する道の追加．
  * `sub_nodes` が循環するサブノードの追加（例：X を Y のサブノードにするとき，Y がすでに X の中にある）．
* 道の両端は，`map_paths` ならこのマップのメインノード，`sub_node_paths` ならそのノードのサブノードでなければならない．
* 生成時の検証（4.2.4）と同じ基準を使う．同じマップでメインノードが別のメインノードの中にも現れることは許す（ADR 0006）．

**後始末**

* **メインノードを外す**:
  * このマップでそのノードに出入りする道（`map_paths`）を消す．前後の道をつなぎ直さない．つなぎ直すと，利用者の意図しない順番ができるためである．
  * そのメインノードの寄り道（`detours`）は連鎖削除する．寄り道から作ったマップは残るが，このマップからの入口はなくなる．
  * そのメインノードの記録（`map_progress_events.map_node_id`）は NULL になり，現在地はその前に開始・完了したノードに戻る（4.2.8）．
  * どのマップの `map_nodes` にも，どのノードの `sub_nodes` にも残らなくなったノードは，マップ削除と同じ規則（4.1.2）で，サブノードを辿って進捗ごと削除する．
* **サブノードを外す**: そのノードの中でサブノードに出入りする `sub_node_paths` を消し，どこにも残らなくなったサブノードは同じ規則で削除する．他のマップのメインノードや，他のノードのサブノードとして残っているものは消さない．
* **元ノードから作ったマップ**（F-017）: メインノードを追加したら元ノードのサブノードにも加え，外したら元ノードのサブノードからも外す．生成時（4.2.4）と同じく，元ノードをドリルダウンした中身と，元ノードから作ったマップの中身をそろえるためである．F-017 の詳細（9章）と合わせて確定する．
* **ゴール到達後の編集**: 未完了のメインノードを追加するとゴール未到達に戻る．完了にした元ノードの進捗は変えない（4.2.8）．

**実行前の確認**

次のいずれかに当たる操作は，すぐには実行せず，`409` とエラーコード `confirmation_required` に影響の内容を添えて返す．クライアントは内容を示して利用者に確認し，同意されたら `confirmed=true` を付けて同じリクエストを送り直す．確認の要否はバックエンドが判定し，Web と CLI で同じにする．

* 操作したマップ以外のマップにも反映される（他のマップに登場するノードの内容・サブノード・サブノード間の道の編集，元ノードのサブノードの変更）．影響するマップの一覧を示す．
* 進捗（学習中または完了）のあるノードが削除される．削除されるノードの一覧を示す．

**同時の編集**

* 2か所（2つのタブ，ブラウザと CLI）から同じノードやマップを編集したときは，**後から保存したほうが勝つ**．古い内容を見て編集したかどうかは確かめない．
* 1人で使うアプリで衝突はまれなため，初期リリースでは防がない（9章）．Web は画面に戻ってきたときに最新を取り直し，保存していない入力があれば別の場所で変更されたことを示す（4.4）．

### 4.3 インタフェース設計

#### 4.3.1 クライアント（フロントエンド・CLI）–バックエンドAPI

REST API を基本としつつ，マップ生成のみストリーミング（Server-Sent Events）で提供する．フロントエンドと CLI（4.5）は同じ API を利用する．ブラウザは Cookie セッション（4.6），CLI は `Authorization: Bearer <token>` ヘッダー（4.5.4）で認証する．ログインしていない（どちらでもユーザーを特定できない）リクエストには，ログイン用の API（`POST /api/auth/:provider`，`GET /api/auth/:provider/callback`，`POST /api/auth/cli_login_requests`，`POST /api/auth/cli_login_requests/token`）を除いて `401` を返す．

| エンドポイント | 概要 |
| :--- | :--- |
| `POST /api/auth/:provider` | Web のログインを始める（F-019，4.6）．`provider` は `google` / `github`．SPA の CSRF トークン付きのフォーム送信で呼び，Google / GitHub のログイン画面へ転送する．`return_to` を受け取る． |
| `GET /api/auth/:provider/callback` | Google / GitHub からの戻り先（4.6）．ユーザーを探すか作り，ログインの Cookie を付けて `FRONTEND_ORIGIN` + `return_to` へ転送する． |
| `GET /api/session` | ログイン中のユーザーと CSRF トークンを返す（4.6）．未ログインなら `401`． |
| `DELETE /api/session` | ログアウト．その端末のセッションだけを消す（4.6）． |
| `POST /api/auth/cli_login_requests` | CLI のログインを始める（4.5.4）．認証なし．CLI のマシン名 `name` を受け取り，`device_code`，`user_code`，`verification_uri`，`expires_in`，`interval` を返す． |
| `POST /api/auth/cli_login_requests/token` | CLI がトークンを受け取りに来る（4.5.4）．認証なし．`device_code` を受け取り，許可されていればトークンを発行して返す．まだなら状態を返す． |
| `POST /api/auth/cli_login_requests/lookup` | S-04 の確認に出す内容（端末名と開始時刻）を返す（4.4）．Web のログインが必要．`user_code` を受け取る． |
| `POST /api/auth/cli_login_requests/approve` | CLI のログインを許可する（S-04）．Web のログインが必要．`user_code` を受け取る． |
| `POST /api/auth/cli_login_requests/deny` | CLI のログインを拒否する（S-04）．Web のログインが必要．`user_code` を受け取る． |
| `DELETE /api/auth/tokens/current` | リクエストに使ったトークンを失効させる（4.5.4）． |
| `GET /api/llm_providers` | 自分の LLM API キーに選べる会社とモデルの候補（ReqDef F-020）． |
| `GET /api/llm_credential` | 自分の LLM API キーの設定の状態（F-020）．会社，モデル，`api_key_last4`，`verified_at` を返し，未設定なら `null`．キーそのものは返さない． |
| `PUT /api/llm_credential` | 自分の LLM API キーを確かめてから保存する（F-020，4.3.2）．`provider`，`model`，`api_key` を受け取る．Web のログイン（Cookie セッション）でだけ受け付ける． |
| `DELETE /api/llm_credential` | 自分の LLM API キーを削除し，サービスのキーに戻す（F-020）．Web のログイン（Cookie セッション）でだけ受け付ける． |
| `GET /api/maps` | ログインユーザーのマップ一覧を取得（F-012）．元ノードや寄り道の出発点の情報を含める． |
| `POST /api/maps` | マップを作り，同時に生成を開始する（F-011）．ゴールと難易度を受け取り，元ノードから作る場合は `origin_node_id`，寄り道から作る場合は `detour_id` を指定する（F-006，F-017）．マップは `generating` で作られ，生成ジョブ（4.2.9）を起動して `201` を返す．生成の様子は `GET /api/maps/:id/generation` で受け取る． |
| `DELETE /api/maps/:id` | マップの削除．ノードの扱いは 4.1.2 に従う．生成中のマップも削除でき，生成ジョブは止まる（4.2.9）． |
| `GET /api/maps/:id/deletion_preview` | 削除前の確認．そのマップで学習中にしたノードと，他のマップに残るノードの数を返す（4.1.2）． |
| `POST /api/goal_suggestions` | 入力に対するゴール候補提案（F-002）．マップを作る前に呼ぶため，マップを指定しない． |
| `GET /api/maps/:id/generation` (SSE) | 生成の様子を受け取る（F-011）．保存済みのノードをすべて送った後，新しく保存されたノードを送り，終端イベントで閉じる．何度つなぎ直してもよい．イベント形式は本節の「SSE イベント形式」を参照． |
| `GET /api/maps/:id` | マップ画面の表示内容．生成の状態，メインノードと道，作成済みの寄り道の入口，元ノードから作ったマップへのリンク，コンパス情報（4.2.8）を返す．コンパス情報は `ready` のときだけ返す． |
| `GET /api/maps/:mapId/nodes/:nodeId` | ノードの詳細．概要，進捗，このマップでの寄り道，そのノードが登場する他のマップ，元ノードとして作ったマップを返す． |
| `GET /api/nodes/:id/sub_nodes` | ドリルダウン（F-007）．指定ノードのサブノード群とその間の道をグラフとして取得する．サブノードはマップ間で共有されるため，マップを指定しない． |
| `PATCH /api/maps/:mapId/nodes/:nodeId/progress` | ノードの進捗ステータス更新（F-010）．どのマップから操作したかを `mapId` で受け取り，そのマップの進捗の履歴（`map_progress_events`）への記録と `started_map_id` の更新を行う（4.2.8）．レスポンスに更新後のコンパス情報を含める． |
| `GET /api/nodes?q=:text&map_id=:mapId` | 既存ノードの提案（F-018）．タイトルに部分一致する自分のノードを返す．`map_id` を指定すると，そのマップで既にメインノードか，どのメインノードの中にあるかを添える（4.2.10）． |
| `POST /api/maps/:mapId/nodes` | メインノードの追加（F-018）．既存ノードを置く場合は `node_id`，新しく作る場合は `title` と `summary`（任意）を受け取る．`importance`（`high` / `mid` / `low`）は任意で，省略時は `mid`． |
| `PATCH /api/maps/:mapId/nodes/:nodeId` | 重要度の変更（F-018）．`importance`（`high` / `mid` / `low`）を受け取る． |
| `DELETE /api/maps/:mapId/nodes/:nodeId` | メインノードをマップから外す（F-018）．後始末は 4.2.10 に従う． |
| `POST /api/maps/:mapId/paths` / `DELETE /api/maps/:mapId/paths?from=:fromId&to=:toId` | このマップの道の追加・削除（F-018）．追加は `from_node_id` と `to_node_id` を受け取る． |
| `PATCH /api/nodes/:id` | ノードの内容（`title`，`summary`）の編集（F-018）．操作したマップを `map_id` で受け取る． |
| `POST /api/nodes/:id/sub_nodes` / `DELETE /api/nodes/:id/sub_nodes/:subNodeId?map_id=:mapId` | サブノードの追加・外す（F-018）．追加は `node_id`（既存ノード）または `title` と `summary`（新規），および `map_id` を受け取る． |
| `POST /api/nodes/:id/sub_node_paths` / `DELETE /api/nodes/:id/sub_node_paths?from=:fromId&to=:toId&map_id=:mapId` | ノードの中のサブノード間の道の追加・削除（F-018）．追加は `from_node_id`，`to_node_id`，`map_id` を受け取る． |

**`POST /api/maps` リクエスト／レスポンス例**

```json
{ "title": "AIエンジニアリング入門", "goal_text": "AIについて深く知りたい", "difficulty": "standard", "origin_node_id": null, "detour_id": null }
```

```json
{
  "id": 123,
  "title": "AIエンジニアリング入門",
  "goal_text": "AIについて深く知りたい",
  "difficulty": "standard",
  "status": "generating",
  "origin_node_id": null,
  "created_at": "2026-07-03T10:00:00+09:00"
}
```

* `title` は，ゴール候補（F-002）を選んだ場合はその候補のタイトル，自由入力のまま進んだ場合は入力した文とする．
* マップの作成と生成の開始を1回のリクエストにまとめるため，生成前の状態は持たない（`status` は作成時から `generating`）．生成をやり直す API はない（4.2.9）．

**`GET /api/session` レスポンス例**

```json
{
  "user": { "id": 1, "name": "池田 琉俊", "email": "user@example.com" },
  "csrf_token": "k9Xn..."
}
```

未ログインの場合（`401`）:

```json
{ "code": "unauthenticated", "message": "ログインしてください．", "csrf_token": "k9Xn..." }
```

* `message` は他のエラーと同じく「コード→文言」の対応表から作る（`unauthenticated`，`invalid_csrf`）．S-05 に示すログインの失敗の理由（`email_not_verified`，`auth_failed`，4.6）も同じ対応表に置く．
* `csrf_token` は Rails 標準の CSRF トークンである．SPA は書き込み系（POST / PATCH / DELETE）のリクエストに `X-CSRF-Token` ヘッダーとして付ける（4.6）．未ログインでも返すのは，S-05 のログインのフォーム送信（`POST /api/auth/:provider`）に必要なためである．
* CSRF トークンがない・合わない，または `Origin` が `FRONTEND_ORIGIN` と一致しない書き込みには `403`（`code`: `invalid_csrf`）を返す（4.6）．

**Bearer トークンが使えない場合の `401` レスポンス例**

ログイン用の API を除くすべてのエンドポイントで共通である．

`Authorization: Bearer <token>` を付けたリクエストで，トークンの `expires_at` を過ぎている場合:

```json
{ "code": "token_expired", "message": "ログインの有効期限が切れました．campass login を実行してください．" }
```

トークンに一致する `api_tokens` の行がない（誤ったトークン，または `campass logout` で失効させた）場合:

```json
{ "code": "invalid_token", "message": "ログインしていないか，ログアウトされています．campass login を実行してください．" }
```

* `message` は他のエラーと同じく「コード→文言」の対応表から作る．
* `Authorization` ヘッダーがあるリクエストは Bearer トークンだけで判定するため（4.6），Cookie セッションがあってもこの `401` になる．

**`POST /api/auth/cli_login_requests` リクエスト／レスポンス例**

```json
{ "name": "my-laptop" }
```

```json
{
  "device_code": "Gm2x...",
  "user_code": "WDJB-MJHT",
  "verification_uri": "https://app.campass.example.com/cli/activate",
  "expires_in": 600,
  "interval": 5
}
```

* `device_code` は CLI だけが知るランダムな長い値で，DB には SHA-256 ハッシュだけを保存する（4.1.2）．
* `verification_uri` は `FRONTEND_ORIGIN` + `/cli/activate` とする．`user_code` は URL に含めない（4.5.4）．

**`POST /api/auth/cli_login_requests/token` リクエスト／レスポンス例**

```json
{ "device_code": "Gm2x..." }
```

許可された場合（`200`）．形は CLI のトークンの発行として共通である:

```json
{ "token": "cmp_3f9a...", "expires_at": "2027-01-04T10:00:00+09:00" }
```

まだトークンを渡せない場合は `400` で，`code` に RFC 8628 と同じ状態を返す:

```json
{ "code": "authorization_pending", "message": "ブラウザでの許可を待っています．" }
```

```json
{ "code": "slow_down", "message": "受け取りの間隔が短すぎます．" }
```

```json
{ "code": "access_denied", "message": "ログインが拒否されました．" }
```

```json
{ "code": "expired_token", "message": "期限切れです．もう一度 campass login を実行してください．" }
```

| `code` | 返す条件 |
| :--- | :--- |
| `authorization_pending` | `pending` で期限内．まだ許可も拒否もされていない |
| `slow_down` | 前回の受け取り（`last_polled_at`）から `interval` 秒たっていない．`slow_down` を返したときも `last_polled_at` を更新する |
| `access_denied` | `denied` |
| `expired_token` | 期限切れ，すでに `consumed`，または `device_code` に一致する要求がない |

* トークンは，許可されたときではなく，CLI がこの API で受け取りに来たときに作る．`approved` の要求の行をロックし，`api_tokens` に1行足して要求を `consumed` にするまでを1つのトランザクションで行う．トークンの平文はこのレスポンスでだけ返し，2回目以降は `expired_token` になる．
* `message` は他のエラーと同じく「コード→文言」の対応表から作る．

**`POST /api/auth/cli_login_requests/lookup` / `approve` / `deny` リクエスト／レスポンス例**

```json
{ "user_code": "WDJB-MJHT" }
```

`lookup` のレスポンス（`200`）:

```json
{ "name": "my-laptop", "created_at": "2026-10-11T10:00:00+09:00" }
```

* `approve` は要求に `user_id` を入れて `approved` に，`deny` は `denied` にし，どちらも `204` を返す．
* 3つとも，`user_code` に一致する要求がない，期限切れ，`pending` でない場合は `404`（`code`: `invalid_user_code`）を返す．
* `user_code` は前後の空白を除き，大文字にそろえ，ハイフンがなくても受け付ける．
* 3つとも Web のログイン（Cookie セッション，4.6）でだけ受け付け，Bearer トークンのリクエストには `401` を返す．書き込みと同じく CSRF トークンと `Origin` を確かめる．`user_code` を URL に残さないため，`lookup` も POST とする．

**`GET /api/llm_providers` レスポンス例**

```json
{
  "providers": [
    { "id": "gemini", "name": "Gemini", "models": [ "gemini-3.1-flash-lite" ] }
  ]
}
```

* 返すのは実装済みの会社（LLM の抽象インタフェースの実装がある会社．4.3.2）だけとする．今は Gemini だけである．
* モデルの候補は，バックエンドの設定ファイル（例：`backend/config/llm_providers.yml`．名前は実装に任せる）で会社ごとに決める．自由なモデル名を受け付けないのは，プロンプトや JSON Schema（4.2.4）が合わないモデルで生成が失敗するのを防ぐためである．

**`GET /api/llm_credential` / `PUT /api/llm_credential` リクエスト／レスポンス例**

`PUT` のリクエスト:

```json
{ "provider": "gemini", "model": "gemini-3.1-flash-lite", "api_key": "AIza..." }
```

レスポンス（`GET` と `PUT` で共通．`200`）:

```json
{
  "llm_credential": { "provider": "gemini", "model": "gemini-3.1-flash-lite", "api_key_last4": "x7Qc", "verified_at": "2026-10-12T10:00:00+09:00" }
}
```

未設定の場合（`GET`）:

```json
{ "llm_credential": null }
```

* キーそのものは，どの応答（`PUT` の成功とエラーの応答を含む）にも含めない．変えるときは，会社・モデル・キーをすべて入力し直して `PUT` する．
* `PUT` は保存の前に，選んだ会社の実装で「キーとモデルを確かめる」（4.3.2）．確かめられたら `verified_at` を現在時刻にして保存する（設定済みなら置き換える）．確かめられなければ保存せず，既存の設定も変えずに次のエラーを返す．`message` は他のエラーと同じく「コード→文言」の対応表から作る．

  | HTTP ステータス | `code` | 意味 |
  | :--- | :--- | :--- |
  | `422` | `api_key_invalid` | 会社がキーを受け付けない（無効なキー，権限がない） |
  | `422` | `model_not_available` | 選んだ会社・モデルが候補（`GET /api/llm_providers`）にない，またはそのキーで使えるモデルの一覧にない |
  | `502` | `llm_api_error` | 会社の API に接続できない，または会社側の障害で確かめられなかった |

* 候補にない会社・モデルは，会社の API を呼ぶ前に `422 model_not_available` にする．
* `PUT` と `DELETE` は Web のログイン（Cookie セッション，4.6）でだけ受け付け，Bearer トークンのリクエストには `401` を返す．CLI から設定させない理由は 4.4 の「設定（S-06）」に示す．書き込みなので，CSRF トークンと `Origin` を確かめる．`GET /api/llm_credential` と `GET /api/llm_providers` は読むだけなので，どちらの認証でも受け付ける．
* 保存のときの `api_key_invalid` は「いま入力したキー」を確かめた結果で，呼び出しのときの `user_api_key_invalid`（下の「SSE イベント形式」）は「保存してあるキー」が使えなかった結果である．利用者に求めることが違う（入力を直す／S-06 で設定を見直す）ため，コードを分ける．
* `DELETE /api/llm_credential` は行を消して `204` を返す（未設定でも `204`）．以後の呼び出しはサービスのキーに戻る．生成中のマップは，始まったときのキーで続く（4.2.9）．

**`POST /api/goal_suggestions` のエラー**

* 利用者のキー（4.3.2）で LLM を呼んで失敗したときは，`422` で `code` に `user_api_key_invalid` / `user_api_key_quota_exceeded` を返す．意味と文言は，本節の「SSE イベント形式」のエラーコードの表と同じ「コード→文言」の対応表から作る．サービスのキーでは呼び直さない．クライアントは S-06 で設定を確かめるよう案内する（4.4）．
* それ以外の LLM の呼び出しの失敗は `502` で `code` に `llm_api_error` を返す．

**`GET /api/maps` レスポンス例**

```json
{
  "maps": [
    { "id": 123, "title": "AIエンジニアリング入門", "difficulty": "standard", "status": "ready", "origin": null, "detour_start": null, "updated_at": "2026-07-03T10:05:00+09:00" },
    { "id": 140, "title": "ベイズ統計", "difficulty": "light", "status": "ready", "origin": null, "detour_start": { "map_id": 123, "map_title": "AIエンジニアリング入門", "node_id": 501, "node_title": "統計学の基礎" }, "updated_at": "2026-07-05T21:30:00+09:00" },
    { "id": 141, "title": "Rust 入門", "difficulty": "light", "status": "failed", "error": { "code": "llm_api_error", "message": "生成サービスに接続できませんでした．" }, "origin": null, "detour_start": null, "updated_at": "2026-07-06T09:12:00+09:00" }
  ]
}
```

* `updated_at` の新しい順に返す（同じなら `id` の大きい順）．`updated_at` の意味は 4.1.2 の `maps` に従う．
* `status` が `failed` のマップは `error`（`code`，`message`）を持つ．`message` はエラーコードの対応表（本節の「SSE イベント形式」）から作る．
* このAPIを呼んだときに，ハートビートが切れた `generating` のマップを `failed`（`timed_out`）にしてから返す（4.2.9）．

**`GET /api/maps/:id` レスポンス例**

```json
{
  "map_id": 123,
  "title": "AIエンジニアリング入門",
  "status": "ready",
  "error": null,
  "origin": null,
  "graph": {
    "nodes": [
      { "id": 501, "title": "統計学の基礎", "importance_score": 0.8, "has_sub_nodes": true, "progress": "completed", "other_map_count": 1, "origin_of_map_id": null, "spawned_detour_map": { "map_id": 140, "title": "ベイズ統計" }, "also_inside": [] },
      { "id": 502, "title": "線形代数の基礎", "importance_score": 0.9, "has_sub_nodes": false, "progress": "not_started", "other_map_count": 0, "origin_of_map_id": null, "spawned_detour_map": null, "also_inside": [] },
      { "id": 503, "title": "微分の基礎", "importance_score": 0.6, "has_sub_nodes": false, "progress": "not_started", "other_map_count": 0, "origin_of_map_id": 150, "spawned_detour_map": null, "also_inside": [] },
      { "id": 504, "title": "確率の基礎", "importance_score": 0.5, "has_sub_nodes": false, "progress": "completed", "other_map_count": 0, "origin_of_map_id": null, "spawned_detour_map": null, "also_inside": [ { "node_id": 501, "title": "統計学の基礎" } ] }
    ],
    "paths": [
      { "from": 501, "to": 502 },
      { "from": 501, "to": 503 }
    ]
  },
  "compass": {
    "current_node_id": 501,
    "candidates": [
      { "node_id": 502, "importance_score": 0.9 },
      { "node_id": 503, "importance_score": 0.6 }
    ],
    "is_goal_reached": false
  }
}
```

* `status` は `generating` / `ready` / `failed` のいずれか．`compass` は `ready` のときだけ返し，それ以外は `null` とする．`error` は `failed` のときだけ `code` と `message` を持ち，それ以外は `null` とする．ハートビートの判定は `GET /api/maps` と同じく行う（4.2.9）．
* `generating` のマップでは，`graph` はその時点までに保存されたメインノードと道である．
* `other_map_count` が1以上のノードはマップ間ノードであり，マップ画面で「他のマップと共通」の印を付ける．
* `origin_of_map_id` は，そのノードを元ノードとして作ったマップ．選ぶとドリルダウンの代わりにそのマップへ移動する．
* `spawned_detour_map` は，そのノードの寄り道から作ったマップ．行き止まりの入口として描く．まだマップを作っていない寄り道はここに含めず，ノードの詳細で返す．
* `also_inside` は，このマップでそのノードを中に含む（深さを問わずサブノードに持つ）別のメインノード．空でなければ「『A』の中にもあります」の印を付ける（ADR 0006）．
* `compass.current_node_id` は，進捗の履歴から導出した現在地である（4.2.8）．メインノードが0個のマップでは `graph.nodes` が空で，`is_goal_reached` は `false` になる．

**`GET /api/maps/:mapId/nodes/:nodeId` レスポンス例**

```json
{
  "id": 501,
  "title": "統計学の基礎",
  "summary": "データの要約と確率の基本を学ぶ",
  "progress": "completed",
  "detour": { "id": 77, "title": "ベイズ統計", "reason": "確率の更新という考え方に触れる", "spawned_map_id": 140 },
  "other_maps": [ { "map_id": 124, "title": "データ分析基礎" } ],
  "origin_of_map_id": null
}
```

**`PATCH /api/maps/:mapId/nodes/:nodeId/progress` リクエスト／レスポンス例**

```json
{ "status": "completed" }
```

```json
{
  "node_id": 503,
  "progress": "completed",
  "compass": { "current_node_id": 503, "candidates": [], "is_goal_reached": true },
  "origin_completion_suggestion": { "node_id": 900, "title": "微積分" }
}
```

* `origin_completion_suggestion` は，この更新でマップがゴールに到達し，マップに元ノードがある場合にだけ返す（それ以外は `null`）．クライアントは元ノードの完了を提案し，完了にするかはユーザーが決める（4.2.8）．

**ノードの編集（F-018）のレスポンス**

* マップに関わる操作（`/api/maps/:mapId/nodes`，`/api/maps/:mapId/paths`）は，成功すると `GET /api/maps/:id` と同じ形のマップ全体（`graph` と `compass`）を返す．道やメインノードが変わるとコンパス候補も変わるためである．
* ノードに関わる操作（`/api/nodes/:id`，`/api/nodes/:id/sub_nodes`，`/api/nodes/:id/sub_node_paths`）は，成功すると `GET /api/nodes/:id/sub_nodes` と同じ形で，そのノードの内容とサブノードを返す．
* 失敗と確認は次の形で返す．`message` は SSE のエラーと同じく「コード→文言」の対応表から作る．

  | HTTP ステータス | `code` | 意味 |
  | :--- | :--- | :--- |
  | `409` | `map_not_ready` | 操作したマップが `ready` でない（4.2.10） |
  | `409` | `confirmation_required` | 実行前の確認が必要．`confirmed=true` を付けて送り直すと実行する（4.2.10） |
  | `422` | `cycle` | 道・サブノード・サブノード間の道が循環する（4.2.10） |
  | `422` | `already_placed` | 置こうとしたノードが，すでにこのマップのメインノードである |
  | `404` | — | マップやノードがない，または他ユーザーのもの |

**`GET /api/nodes?q=確率&map_id=123` レスポンス例**

```json
{
  "nodes": [
    { "id": 504, "title": "確率の基礎", "already_main": true, "inside": [ { "node_id": 501, "title": "統計学の基礎" } ] },
    { "id": 611, "title": "条件付き確率", "already_main": false, "inside": [ { "node_id": 501, "title": "統計学の基礎" } ] },
    { "id": 812, "title": "確率過程", "already_main": false, "inside": [] }
  ]
}
```

* `already_main` が `true` のノードは選べない状態で示す．`inside` は，このマップでそのノードを中に含むメインノードである．

**`POST /api/maps/:mapId/paths` の循環エラー例**

```json
{ "code": "cycle", "message": "この道を引くと循環します：線形代数の基礎 → 行列の積 → 線形代数の基礎", "cycle": [502, 610, 502] }
```

**`DELETE /api/maps/:mapId/nodes/:nodeId` の確認例**

```json
{
  "code": "confirmation_required",
  "message": "この操作は次の内容に影響します．",
  "confirmation": {
    "affected_maps": [ { "map_id": 150, "title": "微積分" } ],
    "deleted_nodes": [ { "node_id": 503, "title": "微分の基礎", "progress": "in_progress" } ]
  }
}
```

* `affected_maps` は操作したマップ以外に反映されるマップ，`deleted_nodes` はこの操作で削除される，進捗のあるノードである．該当がなければ空の配列とする．

**`GET /api/maps/:id/generation` SSE イベント形式**

レスポンスの `Content-Type` は `text/event-stream` とする．各イベントは `event:` 行と `data:` 行（JSON を1行で記載）からなり，空行で区切る（4.5.6 の CLI の受信方式と同じ）．CLI は `Authorization: Bearer <token>` で認証する（4.5.4）．ブラウザは `new EventSource(url, { withCredentials: true })` でつなぎ，ログインの Cookie で認証する（4.6）．`EventSource` はリクエストヘッダーを指定できないが，Cookie セッションなら追加のヘッダーは要らない．

SSE は生成ジョブ（4.2.9）から直接ではなく，DB から読んで送る．接続するたびに次の順で送る．

1. そのマップに保存済みのノードを，保存した順にすべて `node` イベントで送る．
2. マップが `generating` の間は，DB を一定間隔で読み，新しく保存されたノードを `node` イベントで送る．あわせて `status` とハートビート（4.2.9）を確かめる．
3. マップが `ready` / `failed` になった，または削除されたら，終端イベント（`done` / `error` / `deleted`）を送って閉じる．接続したときにすでに `ready` / `failed` なら，1の後すぐに終端イベントを送る．

そのため，同じノードがつなぎ直しのたびに届く．クライアントはノードを ID をキーにして持ち，同じ ID が届いたら上書きする（CLI は表示済みの ID を表示しない）．`id:` 行と `Last-Event-ID` による途中からの再開は使わない．存在しない（削除済みの）マップには `404` を返す．

| イベント名 | 送信タイミング | 概要 |
| :--- | :--- | :--- |
| `node` | 保存済みのノードを送るとき | 完成した1ノード（メインノードまたはサブノード）．トークン断片は送らない（4.3.2）． |
| `done` | マップが `ready` になったとき | 終端イベント． |
| `error` | マップが `failed` になったとき | 終端イベント． |
| `deleted` | マップが削除されたとき | 終端イベント．エラーではない． |

* `node` の `data` は次の項目を持つ．ID はすべて DB 保存後の ID とする．`GET /api/maps/:id` のノード表現と共通する項目は，同じ名前・意味とする．

  | 項目 | 型 | 説明 |
  | :--- | :--- | :--- |
  | `id` | number | `nodes.id` |
  | `title` | string | ノードのタイトル |
  | `summary` | string | ノードの概要 |
  | `is_main` | boolean | このマップのメインノードなら `true`，サブノードなら `false` |
  | `parent_node_id` | number \| null | サブノードの場合，そのサブノードを持つノードの ID．メインノードの場合は `null` |
  | `from` | number[] | このノードへ道がのびてくるノードの ID．メインノードならこのマップの `map_paths`，サブノードなら同じノードの中の `sub_node_paths` |
  | `importance_score` | number \| null | メインノードの場合のみ（0〜1） |
  | `reused` | boolean | 既存ノードを再利用した場合 `true`（F-015） |
  | `progress` | string | 現在の進捗．再利用した既知ノードは学習中・完了で届くことがあり，F-009 の演出に使う |
  | `detour` | object \| null | メインノードの場合のみ．寄り道（`id`，`title`，`reason`） |

* 再利用したノードの既存のサブノードは，そのノードの `node` イベントの後に，`reused: true` の `node` イベントとして送る．
* `done` の `data` は `map_id`，`status`（`"ready"` 固定），`node_count`（送ったノード数）を持つ．
* `error` の `data` は `code`，`message`，`retryable` を持つ．`code` は `maps.generation_error_code` に保存した値である．`message` は利用者に表示してよい文言で，バックエンドが持つ「コード→文言」の対応表から作る（SSE と REST で共通）．内部例外の詳細や API キーは含めず，それらはサーバーログにだけ出す．文言を保存せずコードから作るのは，例外のメッセージをそのまま保存・表示してしまう事故（内部の詳細や API キーの断片の漏えい）を構造上起こさないため，文言を直したときに過去に失敗したマップの表示にも反映されるようにするため，SSE と REST で同じ表現にするためである．`retryable` は，クライアントがマップを削除して作り直すことを勧めてよいかを示す（同じマップでの生成のやり直しはない．4.2.9）．

  | `code` | 意味 | `retryable` |
  | :--- | :--- | :--- |
  | `parse_failed` | LLM 出力のパースに失敗し，リトライ上限（最大2回，4.2.4）を超えた | `true` |
  | `invalid_map` | 道やサブノードの循環，未知の参照，ゴールへつながらないノード，メインノード数が範囲外など 4.2.4 の検証エラー．該当する道やサブノードを黙って除去・修正しない | `true` |
  | `llm_api_error` | LLM API の呼び出しに失敗した | `true` |
  | `user_api_key_invalid` | 利用者が設定した API キーが使えなかった（会社がキーを受け付けない，権限がない，保存したキーを復号できない．4.3.2）．サービスのキーには切り替えない | `true` |
  | `user_api_key_quota_exceeded` | 利用者が設定した API キーで，利用の上限に達した，または支払いの問題で呼び出せなかった．サービスのキーには切り替えない | `true` |
  | `internal_error` | 上記以外のサーバー内部エラー | `false` |
  | `timed_out` | 生成ジョブが一定時間ノードを保存せず，消えたものとみなした（ハートビート切れ．4.2.9） | `true` |

* `user_api_key_invalid` の文言は「設定した API キーが使えませんでした．設定を確かめてください．」，`user_api_key_quota_exceeded` の文言は「設定した API キーの利用の上限に達したか，支払いに問題があります．設定を確かめてください．」とする．どちらも，設定を直してからマップを削除して作り直せるため `retryable` は `true` とする（4.4 で S-06 へ案内する）．
* `deleted` の `data` は `map_id` を持つ．文言の対応表には含めない．

* `done`，`error`，`deleted` は終端イベントであり，サーバーはどれかを送った後に接続を閉じる．クライアントは終端イベントを受け取らずに接続が切れた場合，生成が終わったとはみなさず，同じ `GET` でつなぎ直してよい．接続が切れても生成は続く（4.2.9）．接続が切れても生成を続ける理由と，`Last-Event-ID` ではなく全ノードを送り直す方式にした理由は 5.10 と ADR 0004 に示す．
* 接続維持のため，サーバーはコメント行（`: keep-alive`）を送ってよい．クライアントはコメント行を無視する．

**`GET /api/maps/:id/generation` SSE レスポンス例（正常終了）**

```
event: node
data: {"id":501,"title":"統計学の基礎","summary":"データの要約と確率の基本を学ぶ","is_main":true,"parent_node_id":null,"from":[],"importance_score":0.8,"reused":true,"progress":"completed","detour":{"id":77,"title":"ベイズ統計","reason":"確率の更新という考え方に触れる"}}

event: node
data: {"id":502,"title":"線形代数の基礎","summary":"ベクトルと行列の基本を学ぶ","is_main":true,"parent_node_id":null,"from":[501],"importance_score":0.9,"reused":false,"progress":"not_started","detour":null}

: keep-alive

event: node
data: {"id":610,"title":"行列の積","summary":"行列どうしの掛け算の意味を学ぶ","is_main":false,"parent_node_id":502,"from":[],"importance_score":null,"reused":false,"progress":"not_started","detour":null}

event: done
data: {"map_id":123,"status":"ready","node_count":3}

```

**`GET /api/maps/:id/generation` SSE レスポンス例（エラー終了）**

```
event: node
data: {"id":501,"title":"統計学の基礎","summary":"データの要約と確率の基本を学ぶ","is_main":true,"parent_node_id":null,"from":[],"importance_score":0.8,"reused":true,"progress":"completed","detour":null}

event: error
data: {"code":"parse_failed","message":"マップの生成結果を解析できませんでした．このマップを削除して，もう一度作り直してください．","retryable":true}

```

#### 4.3.2 バックエンド–LLM API

* プロンプトテンプレートはソースコードから切り離して管理する（ReqDef 5.4）．具体的には，YAML等の外部ファイル，または LangChain/LangSmith 等のオーケストレーションツールでのバージョン管理を想定し，無停止でのA/Bテスト・チューニングを可能にする．
* **学習に使わせない API のプラン（ReqDef 5.3）**: 本番のサービスの API キーは，入出力を学習に使わない契約のプランのものだけを使う．リクエストに設定を付けることも，送信前の検証もしない（Gemini API にはリクエストごとの項目がない）．開発中（テスト用のデータしか送らない）は問わない．
  * **Gemini**: 有料のサービス（Paid Services），つまり請求先のアカウントを有効にした Cloud プロジェクトを通した呼び出しでは，プロンプトと応答を製品の改善に使わない．ただし，禁止されている使い方を見つけるためだけに，限られた期間ログに残す．無料のサービス（Unpaid Services）では，入出力を製品の改善と開発に使い，人が読むこともある．したがって本番のキーは，請求先を有効にしたプロジェクトで作る．請求先を有効にしたプロジェクトの無料の枠の中の呼び出しがどちらに当たるかは，規約に明記がないため，有料のサービスに当たるとは決めない．規約: https://ai.google.dev/gemini-api/terms （2026/10/12 に確認．ページの最終更新は 2026/04/28）
  * **OpenAI / Anthropic**: 2社目として足すとき（「2社目の LLM」）に，各社の今の規約を確かめて追記する．
  * **デプロイの手順での確認（運用の決まり）**: 本番にデプロイするときと本番の API キーを替えるときに，そのキーが学習に使わない契約のプランのもの（Gemini なら請求先を有効にしたプロジェクトのキー）であることを確かめる．`LLM_PROVIDER` を替えるときは，そのプロバイダの規約を先に確かめる．
  * **利用者の API キー（ReqDef F-020）**: 利用者が自分のキーで送る分は，この約束の対象外とする．入出力は利用者とその会社との契約の規約に従って扱われ，S-06 でそのことを示す（4.4）．利用者のキーはデプロイの手順でも確かめない．
* ストリーミングレスポンスは，LLM側のトークン単位のストリームをバックエンドで「1ノード分のJSONが確定した時点」でバッファリングし直し，ノード単位で DB に保存する．クライアントへは，SSE が DB から読んだノードをノード単位のイベントとして送る（4.2.9）．これにより，フロントエンドはトークン断片ではなく意味のある単位で描画できる．イベント名とペイロードの形式は 4.3.1 の「SSE イベント形式」に定める．
* **LLM の抽象インタフェース**: バックエンドに LLM を呼ぶための抽象インタフェースを置く．役割は次の2つだけとする．ノードの切り出し，検証，保存はインタフェースの外に置き，LLM の種類に関係なく共通にする．外部サービスへの依存を小さくし，LLM を替えても変わる範囲をインタフェースの実装だけにするためである．使うキーとモデルは，実装を作るときに外から渡す（サービスのキーか利用者のキーかを，実装は知らない）．名前や形は実装に任せる．生成ジョブのテスト（7章）は，このインタフェースの偽物を使う．
  * **生成する**: システムプロンプト，会話の履歴，JSON Schema（またはツール）を受け取り，結果のテキストの断片をストリームで返す．
  * **キーとモデルを確かめる**（ReqDef F-020）: キーが有効か，選んだモデルがそのキーで使えるかを返す．利用者のキーを保存する前（4.3.1 の `PUT /api/llm_credential`）に呼ぶ．確かめ方は会社ごとに違うため，会社ごとの実装に置く．Gemini はモデルの一覧の API（`GET /v1beta/models`．モデルを動かさないため費用がかからない）を呼び，`nextPageToken` があれば続きもたどって，選んだモデルが一覧にあるかを見る．上限や支払いの問題で実際にモデルを動かせるかは確かめない．最初の生成で失敗したら `user_api_key_quota_exceeded` で知らせ，S-06 で設定を見直すよう案内する（4.4）．
* **最初の実装（Gemini）**: Gemini の REST API を Faraday で直接呼ぶ（`streamGenerateContent?alt=sse`，`systemInstruction`，`responseJsonSchema`）．キーは URL のクエリ（`?key=`）ではなく `x-goog-api-key` ヘッダーで渡し，URL を記録するログにキーが残らないようにする（6章）．`google-genai` gem（0.1.1）は，ストリーミングも `systemInstruction` も扱えないため使わない．Faraday は `google-genai` の依存としてすでに入っており，新しい gem は増えない．`google-genai` gem は Gemfile から外さない（外すかどうかは #20 の範囲外とし，後で決める）．
* **LLM の選び方**: サービスのキーで呼ぶ LLM は，環境変数 `LLM_PROVIDER`（初期値 `gemini`）と `LLM_MODEL`（初期値 `gemini-3.1-flash-lite`）で選んだ1社とする．サービスの API キーは会社ごとの環境変数に置く（今は `GEMINI_API_KEY`）．利用者のキー（ReqDef F-020）では，実装済みの会社と，会社ごとに設定ファイルで決めた候補のモデルから選べる（4.3.1 の `GET /api/llm_providers`）．
* **キーの使い分け（ReqDef F-020）**:
  * 利用者が `user_llm_credentials` を持っていれば，その利用者のすべての LLM の呼び出し（マップの生成，ゴール候補の提案）に，そのキーと会社・モデルを使う．なければサービスのキーを使う．
  * 利用者のキーが使えなかったときは，サービスのキーに切り替えずに失敗にする．黙って切り替えると，運営の費用が増え，学習に使わせない約束（上）の範囲も利用者の知らないうちに変わるためである．会社の応答を `user_api_key_invalid`（キーが無効，権限がない）と `user_api_key_quota_exceeded`（利用の上限，支払いの問題）に分ける（4.3.1）．分け方は会社ごとの実装で決める．Gemini では，キーが無効・権限がないことを示す応答（`API_KEY_INVALID`，`PERMISSION_DENIED`）を前者に，`429 RESOURCE_EXHAUSTED` を後者に当てる（実装時に実際の応答で確かめる）．どちらも，パースの失敗や検証エラーと違って同じキーでは直らないため，再試行（4.2.4）しない．
  * 保存したキーを復号できない（暗号化の鍵をなくした．6章）ときも `user_api_key_invalid` とし，S-06 で設定し直してもらう．
  * 生成ジョブは，始まったときのキーを最後まで使い続ける（4.2.9）．ゴール候補の提案は，リクエストのときのキーを使う．
* **2社目の LLM**: OpenAI や Anthropic を足すときは，Gemini と同じようにプロトタイプでスキーマや件数の扱い（4.2.4 の「構造化出力に特有の点」）を確かめてから実装する．複数の LLM をまとめて扱う LiteLLM（プロキシとして使う案）は，そのときに検討する．

### 4.4 UI/UX設計方針（認知負荷の軽減）

ReqDef 5.1 が求める「認知負荷の軽減」を満たすため，フロントエンドはマップ画面を以下の方針で構成する．マップは「全体を俯瞰できる地図」であると同時に，コンパスによって「今どこへ進めるか」に意識を集中させる画面と位置付ける．

**画面と URL**

| 画面 | URL | 内容 |
| :--- | :--- | :--- |
| S-02 初期入力 | `/maps/new` | 興味，ゴール，難易度．寄り道から作る場合は寄り道のテーマを興味として入力済みにする． |
| S-03 マップ画面 | `/maps/:mapId` | ノードを選んでいる状態は `?node=:nodeId` で表し，ブラウザの戻る・再読み込みで選択を保つ．ドリルダウンも同じパラメータで表す．元ノードや寄り道から作ったマップでは，マップのタイトルの下に「Ruby の『オブジェクト指向』から」「Ruby の『Web アプリ開発』からの寄り道」のような注記を付ける．上部のメニューに「このマップを削除」を置く（下の「マップの削除」）． |
| S-04 CLI ログインの承認 | `/cli/activate` | `campass login` が表示したコードを入力し，CLI のログインを許可・拒否する（4.5.4）．内容は下の「CLI ログインの承認（S-04）」に従う． |
| S-05 ログイン | `/login?return_to=:path` | 「Google でログイン」「GitHub でログイン」の2つのボタンだけを置く（F-019）．未ログインでどの画面を開いてもここへ移り，ログイン後は `return_to` の画面へ戻る．ログインに失敗して戻った場合は理由を示す（4.6）． |
| S-06 設定 | `/settings` | 自分の LLM API キーの設定（F-020）．内容は下の「設定（S-06）」に従う． |

* マップ一覧の画面は持たない．マップ一覧は S-02・S-03・S-06 に出すサイドバー（下の「サイドバー」）とし，マップを切り替えやすくする．
* `/`・`/maps`・ログイン直後（`return_to` がないとき．4.6 で `/maps` へ転送される）は，`GET /api/maps` を呼び，`updated_at` が最新のマップの S-03 へ移る．マップがなければ S-02 へ移り，「最初のマップを作りましょう」と案内する．`/maps` は転送だけを行い，画面を持たない．

**サイドバー**

マップ一覧（F-012）は，S-02・S-03・S-06 に出す開閉できるサイドバーとする．S-04 と S-05 には出さない．サイドバーは移動のためのもので，情報を増やさない（ReqDef 5.1）．一覧の画面をやめた理由は ADR 0007 に記す．

* 中身：
  * 上に「＋ 新しいマップ」を置き，S-02 へ移る．
  * その下にマップのタイトルを `GET /api/maps` の順のまま並べ，今開いているマップを強調する．選ぶとそのマップの S-03 へ移る．
  * 生成中のマップにはスピナー，失敗したマップには S-03 と同じ警告アイコンを付ける（下の「生成の状態」）．
  * 元ノードや寄り道からの注記，削除のボタン，進捗は出さない．注記は S-03 のマップのタイトルの下に，削除は S-03 の上部のメニューに置く．
  * いちばん下に，設定（S-06）への入口（歯車のアイコンと「設定」）を置く．S-06 を開いている間は，入口を強調する．
* 広い画面（幅 768px 以上）では，サイドバーをマップの左に**並べ**，マップの表示領域をその分だけ狭める．開閉しても，マップの見ている中心を保つ．開いていても，マップの操作（ノードの選択，ドラッグ，拡大縮小，詳細パネル，編集）はすべてふつうに使える．
  * 重ねない理由：重ねると，最初の視点（現在地とその周辺）がサイドバーの下に隠れてずれる，「全体を表示」で収めた範囲の一部が隠れてずれる，隠れたノードを操作できない，の3つが起きるためである．
* 狭い画面（幅 768px 未満）では，サイドバーをマップの上に**重ねる**．背景は暗くせず，見えている部分のマップは操作できる．マップを選んだときだけ自動で閉じる（選んだマップが隠れないように）．
* 開閉は ☰ のボタンと，サイドバーの中の閉じるボタンだけで行う．`Esc` や外側を押しても閉じない．開いていてもフォーカスはサイドバーに閉じ込めない．☰ のボタンには開閉の状態を表す `aria-expanded` を付ける．
* 開閉の状態は `localStorage` に，広い画面と狭い画面で別々に覚え，画面を移っても，再読み込みしても保つ．初めては，広い画面では開いた状態，狭い画面では閉じた状態から始める．`localStorage` が使えないときは，この初期値で動く．

**生成から最初の表示まで**

1. S-02 で難易度を選ぶと `POST /api/maps` でマップを作って生成を始め，すぐに S-03 に移る．マップは空で，「マップを作っています」と表示する．
2. S-03 は `GET /api/maps/:id/generation` の SSE につなぐ．`node` イベントが届くたびにノードを1つずつ描き，道でつなぐ．再利用された既知ノードは最初から埋まった状態で現れ，そこから新しいノードへ道がのびるアニメーションを出す（F-009）．
3. 生成中もノードを選んで詳細を読める．ただし，コンパスは生成が終わる（`done`）まで出さない．生成の途中では候補が後から変わるためである．
4. 生成が終わる（`done`）とコンパスを表示する．
5. ユーザーが初めて S-03 を開いたときだけ，「現在地」「コンパス」「ノードを選ぶと詳細とサブノードが見られる」の3つを順に指す短い説明を重ねて出す（「次へ」「スキップ」付き）．2つ目以降のマップでは出さない．専用のオンボーディング画面は作らない．

**生成の状態**

生成はページを離れても続く（4.2.9）．S-03 を開いたときは `GET /api/maps/:id` の `status` で振る舞いを分ける．生成を始める `POST /api/maps` を呼ぶのは S-02 だけである．

| `status` | S-03 の振る舞い |
| :--- | :--- |
| `generating` | 保存済みのノードを描き，`GET /api/maps/:id/generation` の SSE につないで続きを受け取る．コンパスは出さない． |
| `ready` | 通常の表示． |
| `failed` | 保存済みのノードを描く．コンパスは出さない．黄色（濃いめの琥珀色）の警告アイコンと失敗の理由（`error.message`）を示し，マップを削除して作り直すよう案内する（削除ボタン）．`error.code` が `user_api_key_invalid` / `user_api_key_quota_exceeded` なら，S-06 への「設定を確かめる」も添える． |

* SSE で届くノードは ID をキーにして状態に持ち，同じ ID が届いたら上書きする．つなぎ直しで保存済みのノードがもう一度届いても，重複して描かない．終端イベントを受け取らずに接続が切れたら，同じ `GET` でつなぎ直す．
* 生成中に `error` を受け取ったら，`failed` と同じ表示に切り替える．
* サイドバーでは，生成中のマップにスピナーを，失敗したマップに S-03 と同じ黄色の警告アイコンを付ける．どちらも文字のバッジは出さず，`aria-label`（「作成中」「作成に失敗」）でスクリーンリーダーに状態を伝える．色や動きだけに頼らないよう，失敗はアイコンの形でも区別する．

**マップ**

* 初期表示ではメインノードのみを描き，個々のノードの詳細（`summary` 等）は出さず，タイトルと道のみを見せることで情報量を制御する．
* 初期表示の視点は現在地とその周辺（現在地へ道がのびるノード，コンパス候補）に寄せ，全体はユーザーが能動的に広げて眺める．
* ノードを選ぶと詳細パネルを開く（`GET /api/maps/:mapId/nodes/:nodeId`）．詳細パネルには概要，進捗，寄り道（あれば），そのノードが登場する他のマップを示し，そこからサブノードを展開できる（F-007，4.2.6）．
* マップ間ノードには「他のマップと共通」の印を付ける．
* 同じマップの別のメインノードの中にも現れるメインノード（`also_inside`）には「『A』の中にもあります」の印を付ける（ADR 0006）．
* メインノードが0個のマップでは，「メインノードがありません．ノードを追加してください」と表示する．
* 元ノードには「中にマップがある」印を付け，選ぶとドリルダウンの代わりにそのマップへ移動する（F-017）．
* 寄り道は，まだマップを作っていない間は詳細パネルにだけ表示し，マップには描かない．寄り道からマップを作ったら，寄り道の出発点から点線でのびる行き止まりの入口として描き，選ぶとそのマップへ移動する．寄り道の入口は進捗を持たず，コンパスの計算にも使わない（F-006）．
* 別のマップへ移動した後は，ブラウザの戻ると，画面上部の「← 来たマップへ戻る」で戻る．マップ間ノードにより同じマップへ複数のマップから来られるため，固定の階層を表すパンくずリストは作らない．

**コンパス**

* マップ上で現在地を明示し，コンパスが候補（4.2.8）をすべて指し示す．`importance_score` の最も高い候補を強調し，迷ったときの目安にする．
* 候補を選ぶとそのノードの詳細を表示し，学習を開始できる（進捗を `in_progress` に更新）．候補でないノードも開始できる．
* 現在地がない場合（スタート地点）でも，候補の決め方は同じである．道がのびてこないノードや，手前がすべて既知ノードであるノードが候補になる．
* 全ノード完了時（`is_goal_reached = true`）は，ゴール到達を示す表示に切り替える．`origin_completion_suggestion` が返った場合は，元ノードを完了にするかを尋ねる．

**マップの編集（F-018）**

* 編集は `ready` のマップでだけ行える．`generating` と `failed` のマップでは編集の操作を出さない．
* メインノードの追加は，マップ上の操作から行う．タイトルの入力中に `GET /api/nodes?q=` で既存ノードを一覧に出し，選べば既存ノードを置き，選ばなければ新しく作る．すでにメインノードのものは選べない状態で，別のメインノードの中にあるものは「『A』の中にもあります」を添えて示す．
* ノードの内容の編集，マップから外す，重要度（高・中・低）の変更，サブノードとサブノード間の道の編集は，詳細パネルから行う．道はマップ上で2つのノードを選んで引く・消す．
* `409 confirmation_required` が返ったら，影響するマップの一覧と，削除される進捗のあるノードを示して確認し，同意されたら `confirmed=true` で送り直す．
* `422 cycle` が返ったら，循環するノードの並びを含む `message` を示し，マップは変えない．

**マップの削除**

* 削除の前に `GET /api/maps/:id/deletion_preview` の結果を示し，このマップで学習中にしたノードは他のマップで通常の学習中ノードとして扱われること（既知ノードにはならないこと）を注意として知らせる．
* 生成中のマップも削除できる．その場合は確認に「作成中です．削除すると作成も止まります」を添える．「中止」という言葉は使わない．
* 削除は，S-03 の上部のメニューの「このマップを削除」から行う．
* 自分のタブで削除したときは，何も表示せずに，残りのうち `updated_at` が最新のマップの S-03 へ移る．残りのマップがなければ S-02 へ移る．
* 別の場所（別のタブや CLI）で削除されたマップは，次のときに気づく．
  * 開いている S-03 が SSE で `deleted` を受け取ったとき．`deleted` が届くのは，常に別の場所で削除されたときである（自分のタブで削除したときは，先に自分で接続を閉じて別の画面へ移るため）．
  * 開いている S-03 で API を呼んで `404` が返ったとき．
  * マップ一覧を取得したとき（下の「一覧と表示の同期」）．前回取得した一覧にあり，今回の一覧になく，このタブで削除したものでもないマップを，別の場所で削除されたものとみなす．
* 気づいたら，今いる画面のまま，別の場所で削除されたマップをまとめて1つのお知らせで示す（「別の画面で次のマップが削除されました：…」．OK で閉じる）．今開いているマップが削除されていたら，自分のタブで削除したときと同じ規則で移ってからお知らせを出す．マップごとにお知らせを出さない．エラーではないため，警告アイコンは使わない．
* 削除を知らせるためのプッシュは行わない．アプリを閉じている間に削除されたマップは知らせない（比べる前回の一覧がないため）．

**一覧と表示の同期**

* マップ一覧（`GET /api/maps`）は，サイドバーが開いていて，タブが表示されている（`document.visibilityState === 'visible'`）間だけ，30秒ごとに取得する．サイドバーを開いたときと，画面に戻ってきたとき（下の判定．サイドバーが閉じていても）は，すぐに1回取得する．
  * 理由：サイドバーに生成の状態（スピナー，警告アイコン）と削除をすぐ反映するため，開いている間だけ一覧をポーリングする．閉じている間は一覧が見えないので取得しない．
* 開いている S-03 の内容は，**画面に戻ってきたときだけ** `GET /api/maps/:id` で取り直す．定期的なポーリングと，サーバーからのプッシュはしない．
  * 理由：Campass は1人で使うアプリで，ほかの場所（CLI，別のタブ）での変更は，利用者がそちらにいる間に起きる．戻った瞬間に取り直せば，ほとんどの場合に足りる．ノードはマップ間で共有なので（ADR 0003），「このマップが変わったか」を軽く調べるには共有のノードの変更まで追う必要があり，ポーリングやプッシュの仕組みが重くなる．困るのは，ブラウザを一度も操作せずに2つの画面を並べて見ている場合だけである．
  * 生成中のマップは，今のとおり SSE で受け取る（4.2.9，上の「生成の状態」）．
* 「画面に戻ってきた」は，次のどちらかが起きたときとする．
  * `document` の `visibilitychange` で `visibilityState` が `visible` になったとき（タブの切り替え）．
  * `window` の `focus` のとき（端末からブラウザのウィンドウに戻ったときは，`visibilitychange` が起きないため）．
  * 両方が続けて起きることがあるので，直前に取り直してから2秒以内なら取り直さない．
* 取り直した内容は，次の規則で反映する．
  1. マップ（ノード，道，印）とコンパスは，取り直した内容にそのまま置き換える．視点（見ている位置）と拡大率は保つ．
  2. 詳細パネルを開いていたら，そのノードの詳細（`GET /api/maps/:mapId/nodes/:nodeId`）も取り直す．
  3. 選んでいたノードがマップから外されていたら，詳細パネルを閉じ，`?node=` を消し，「このノードはマップから外されました」と知らせる．
  4. 編集の途中（まだ保存していない入力がある）で，取り直したそのノードの内容が入力を始めたときから変わっていたら，入力は消さず，「このノードは別の場所で変更されました」と表示して，「入力を捨てて最新を表示」を選べるようにする．変わっていなければ何も表示しない．
  5. マップ自体が削除されていたら（`404`），上の「マップの削除」の規則（`updated_at` が最新のマップか S-02 へ移り，知らせる）に従う．

**設定（S-06）**

自分の LLM API キーを設定する画面（ReqDef F-020）．サイドバーの下の歯車から開く．

1. `GET /api/llm_providers` と `GET /api/llm_credential` を呼ぶ．
2. 未設定なら「今はサービスのキーで動いています」と示し，会社とモデルを選ぶ欄と，キーの入力欄を置く．会社とモデルは `GET /api/llm_providers` の候補から選ばせ，自由な入力は受け付けない．キーの入力欄は `type="password"`，`autocomplete="off"` とする．
3. 「保存」で `PUT /api/llm_credential` を呼ぶ．確かめている間は「キーを確かめています」と示す．成功したら入力欄を空にし，キーをフロントエンドの状態にも `localStorage` にも残さない．`422` / `502` が返ったら `message` を示し，保存されていないことを伝える．
4. 設定済みなら，会社，モデル，`••••` + `api_key_last4`，確かめた日時（`verified_at`）を示し，「入力し直す」と「削除」を置く．キーそのものは表示しない（バックエンドも返さない）．「入力し直す」は2と同じ欄を開き，会社・モデル・キーをすべて送り直す．
5. 「削除」は確認してから `DELETE /api/llm_credential` を呼び，「サービスのキーに戻しました」と示す．
6. 画面には常に「自分のキーで送った入力は，あなたと〇〇（選んでいる会社の名前）との契約の規約に従って扱われます」と示す（4.3.2 の学習に使わせない API のプランの対象外であるため）．
7. 「作成中のマップは，作成を始めたときのキーで最後まで作ります」と添える（4.2.9）．

* CLI からは設定できない．キーを端末に入力させると画面に表示されてしまい，引数や環境変数で渡すとシェルの履歴やプロセスの一覧に残るためである（CLI でパスワードを扱わない理由（4.5.4，5.12）と同じ）．`PUT` / `DELETE /api/llm_credential` も Bearer トークンでは受け付けない（4.3.1）．
* 利用者のキーで失敗したゴール候補の提案（S-02，`422` の `user_api_key_invalid` / `user_api_key_quota_exceeded`）では，`message` に添えて S-06 への「設定を確かめる」を出す．失敗したマップ（S-03）は上の「生成の状態」に従う．

**CLI ログインの承認（S-04）**

1. 未ログインで `/cli/activate` を開くと，他の画面と同じく S-05 `/login?return_to=/cli/activate` へ移り，ログイン後に `/cli/activate` へ戻る（4.6）．
2. コードの入力欄を1つ置く．「ターミナルに表示されたコードを入力してください」と添える．URL からコードを受け取って入力済みにすることはしない（4.5.4）．
3. 入力したら `POST /api/auth/cli_login_requests/lookup` を呼び，確認画面に端末名（`name`．なければ「名前のない端末」）と開始時刻（`created_at`）を出す（例：「my-laptop からのログイン（10:00 に開始）を許可しますか？」）．「自分で `campass login` を実行していない場合は拒否してください」と添え，「許可」「拒否」を選ばせる．
4. 「許可」は `…/approve`，「拒否」は `…/deny` を呼ぶ．終わったら「ログインを許可しました．ターミナルに戻ってください」または「ログインを拒否しました」を表示する．
5. `404 invalid_user_code` が返ったら「コードが正しくないか，期限が切れています」と表示し，入力し直せるようにする．

### 4.5 CLI設計（F-014）

#### 4.5.1 方針

* CLI はフロントエンドと同列の「バックエンドAPIのクライアント」であり，4.3.1 の API のみを利用する．コンパス（4.2.8），道やサブノードの検証，既存ノードの再利用といった業務ロジックは持たず，バックエンドが返した結果をそのまま表示する．これにより，フロントエンドと CLI で表示内容が食い違わない．
* 外部LLM API を直接呼ばず，そのAPIキーも保持しない（ReqDef 5.3）．
* 実行ファイルの依存は，Go の標準ライブラリと `github.com/spf13/cobra`（cobra が使う `spf13/pflag`・`inconshreveable/mousetrap` を含む）だけとする．コマンドの解析は cobra で行い，HTTP と SSE の受信は標準ライブラリ（`net/http`，`encoding/json`，`bufio` 等）で書く．ほかの外部パッケージは承認を得てから加える．依存を絞るのは，単一の実行ファイルとして配布しやすく（ReqDef 5.1），依存パッケージの更新・脆弱性対応の負担を小さくするためである．cobra を採った理由は 5.5 に示す．
* OpenAPI の定義から型を作る oapi-codegen は，型の生成（`-generate types`）にだけ使う．開発のときだけ使うツールで，実行ファイルには入らない（導入は別の作業で行う）．
* 接続先のバックエンドは，ビルド時に埋め込んだ本番の URL（4.5.8）を既定とする．環境変数 `CAMPASS_API_URL` があれば，それで上書きする（開発中など）．
* すべてのリクエストに `User-Agent: campass-cli/<バージョン>` を付ける．古い CLI を断る仕組みは今は設けない（9章）．

#### 4.5.2 構成

CLI はリポジトリのルートの `cli/` に置く（`backend/`，`frontend/` と並ぶ．リポジトリ全体の構成は基本設計書 2.5 を参照する）．開発時は Docker Compose の `cli` サービス（Go の公式イメージ）で `docker compose run --rm cli go test ./...` のように動かす．

```
cli/
├── go.mod
├── cmd/campass/main.go   # エントリポイント．cobra のルートコマンドを実行するのみ
└── internal/
    ├── command/          # コマンド層：cobra のサブコマンド定義・対話入力（version，completion を含む）
    ├── api/              # API通信層：REST，SSE 受信，トークンと User-Agent の付与
    ├── render/           # 表示層：マップ・コンパス・ノード詳細のテキスト出力
    ├── config/           # 接続先（埋め込みの既定値と CAMPASS_API_URL）とトークンの読み書き
    └── version/          # バージョン（ビルド時に -ldflags -X で埋め込む．既定は dev）
```

レイヤーの役割は基本設計書 2.4，コマンド一覧は基本設計書 3.5 を参照する．

* `campass version` はバージョンを表示する．ローカルでのビルド（埋め込みなし）では `dev` と表示する．
* `campass completion bash|zsh|fish|powershell` はシェルの補完スクリプトを出力する（cobra の機能）．

#### 4.5.3 マップ作成の対話フロー（`campass new`）

3.2 のステップ1〜6を，ターミナル上の対話として順に行う．

1. 興味を自由入力させ，ゴール候補（F-002）が返った場合は番号付きで表示して選ばせる．再入力の扱いは 4.2.1 に従い，バックエンドが判定する．
2. 難易度（ライト／スタンダード／ディープ）を番号で選ばせる（F-003）．
3. `POST /api/maps` でマップを作って生成を始める．
4. `GET /api/maps/:id/generation` の SSE を受信し，ノードが1件届くたびにタイトルと種別（メイン／サブ）を1行で表示する（4.5.6）．再利用したノードには「共通」の印と進捗を付ける．
5. `done` を受け取ったら `GET /api/maps/:id` を呼び，マップとコンパスを表示する（4.5.5）．

ゴール候補の提案や生成が `user_api_key_invalid` / `user_api_key_quota_exceeded`（4.3.1）で失敗したら，`message` に添えて，ブラウザで設定（S-06 `/settings`）を確かめるよう案内する．CLI からはキーを設定できないためである（4.4）．生成の失敗では，設定を直してから `campass delete` で削除して作り直せることも添える．

生成中に Ctrl+C を押しても，バックエンドの生成は続く（4.2.9）．CLI は終了する前に「生成は続いています．`campass map <map_id>` で確認できます」と表示する．

#### 4.5.4 認証

CLI はパスワードを扱わない．`campass login` は，ブラウザで Web にログインして許可してもらう方式（RFC 8628 のデバイスコード方式）でトークンを受け取る．Web のログイン方法には依存せず，Web にログインページがあることだけを前提とする．方式を選んだ理由は 5.12 に示す．

1. `campass login` は `POST /api/auth/cli_login_requests`（認証なし）を呼ぶ．`name` には `os.Hostname()` で取ったマシン名を入れる．レスポンスは `device_code`，`user_code`，`verification_uri`，`expires_in`，`interval`（4.3.1）．
2. CLI は `verification_uri` と `user_code` を表示し，ブラウザを開こうとする（`os/exec` で macOS は `open`，Linux は `xdg-open`，Windows は `rundll32 url.dll,FileProtocolHandler` を呼ぶ）．開けなければ，表示した URL を手で開くよう案内する．

   ```
   ブラウザで次の URL を開き，コードを入力してください．
     URL:    https://app.campass.example.com/cli/activate
     コード: WDJB-MJHT
   ```

3. 利用者はブラウザで S-04 `/cli/activate` を開き，コードを入力して，端末名と開始時刻を確かめてから許可する（4.4）．未ログインなら S-05 でログインしてから戻る．
4. CLI は `interval` 秒（5秒）ごとに `POST /api/auth/cli_login_requests/token`（認証なし）に `device_code` を送る．
   * `authorization_pending`：そのまま待つ．
   * `slow_down`：間隔を5秒延ばして待つ．
   * `access_denied`：「ログインが拒否されました」と表示して終わる．
   * `expired_token`：「期限切れです．もう一度 `campass login` を実行してください」と表示して終わる．
   * `200`：`token` と `expires_at` を受け取り，下のとおり保存して終わる．
5. 待っている間に Ctrl+C を押されたら（`os/signal` で受け取る），改行を出して終了コード 130 で終わる．端末の設定は変えていないため，元に戻す処理は要らない．

* `verification_uri` に `user_code` を含めない．含めると，他人が自分の端末で始めたログインのリンクを踏ませて「許可」させるフィッシングが成り立つためである．利用者が自分のターミナルに表示されたコードを打つことで，許可するのが自分の端末だと確かめさせる．
* `user_code` は8文字の `XXXX-XXXX` とし，打ち間違えやすい文字（`0`/`O`，`1`/`I` など）と数字・母音を避けた20文字（`BCDFGHJKLMNPQRSTVWXZ`）から作る．使い捨てで，同じ値を二度使わない．
* ログイン要求の有効期限は10分とする（`expires_in` = 600）．
* トークンは，許可されたときではなく，CLI が受け取りに来たときに作る（4.3.1）．一度だけ返し，要求を `consumed` にする．バックエンドはトークンの SHA-256 ハッシュのみを `api_tokens` に保存し，平文は保存しない．`api_tokens.name` には要求の `name` を入れる．
* CLI はトークンを `os.UserConfigDir()` 配下の `campass/credentials.json` に，所有者のみ読み書きできる権限（0600）で保存する．
* 以後のリクエストには `Authorization: Bearer <token>` を付ける．
* トークンの有効期限は最後に使ってから30日とする（スライド式）．発行時に `expires_at` = 発行時刻 + 30日 とする．Bearer トークンで認証できたリクエストでは，`last_used_at` が NULL か1日以上前のときだけ，`last_used_at` = 現在時刻，`expires_at` = 現在時刻 + 30日 に更新する．リクエストのたびに書き込まないのは，読むだけのリクエストにも DB への書き込みが毎回加わるのを避けるためである（そのため期限は，最後に記録された利用から30日となり，実際の最後の利用からは最大1日早く切れ得る）．絶対的な上限は設けず，使い続けていればずっと有効とする．
* `expires_at` を過ぎたトークンには `401`（`code`: `token_expired`），一致する行がないトークン（誤ったトークン，`campass logout` で失効させたトークン）には `401`（`code`: `invalid_token`）を返す（4.3.1）．期限切れの行は消さず，使えないとするだけにする（掃除は 9章）．
* CLI は `401` を受けたら，ローカルのトークンファイル（`campass/credentials.json`）を消し，次のメッセージを表示して終了コード 1 で終わる．
  * `token_expired`：「ログインの有効期限が切れました．`campass login` を実行してください」
  * `invalid_token`：「ログインしていないか，ログアウトされています．`campass login` を実行してください」
* `401` を受けても，CLI は自動で `campass login` を始めない．スクリプトから呼ばれたときに，ブラウザでの許可を待って止まってしまわないようにするためである．
* `campass logout` は `DELETE /api/auth/tokens/current` でトークンを失効させてから，ローカルのファイルを削除する．
* Cookie セッションではなくトークン方式とする理由は 5.6 を参照する．

#### 4.5.5 マップとコンパスのテキスト表示（`campass map`）

一本道ビューは廃止されているため（4.2.5），CLI でもノードを「学習する順番」に見える一列として表示しない．表示はコンパスを主とし，グラフは各ノードへ道がのびてくるノードとして示す．

```
コンパス
  現在地: 統計学の基礎 (#501)
  コンパス候補:
    ★ 線形代数の基礎 (#502)  重要度 0.90
      微分の基礎     (#503)  重要度 0.60

マップ
  #501 統計学の基礎    [完了]   共通: データ分析基礎
       └ 寄り道のマップ: ベイズ統計 (map #140)
  #502 線形代数の基礎  [未着手] ← 道: #501
  #503 微分の基礎      [未着手] ← 道: #501   マップあり: 微積分 (map #150)
  #504 確率の基礎      [完了]   中にもある: #501 統計学の基礎
```

* コンパス候補は `compass.candidates` の並び（4.2.8）のまま表示し，先頭の候補に印（★）を付ける．CLI では並べ替えない．
* マップの各行は，メインノードと，そのノードへ道がのびてくるノードを示す．行の並びは API レスポンスの順であり，学習順の意味を持たない．
* マップ間ノードには「共通:」として他のマップ名を付ける．同じマップの別のメインノードの中にも現れるメインノードには「中にもある:」としてそのメインノードを付ける（ADR 0006）．元ノードには「マップあり:」，寄り道から作ったマップは寄り道の出発点の下に字下げして示す（F-006，F-017）．まだマップを作っていない寄り道は `campass show` で表示する．
* `is_goal_reached` が `true` の場合は，候補の代わりにゴール到達を表示する．
* マップが `generating` の場合，`campass map` は `GET /api/maps/:id/generation` の SSE につなぎ，`campass new` と同じくノードを1行ずつ表示してから，`done` を受け取ったらマップとコンパスを表示する．
* マップが `failed` の場合は，保存済みのメインノードと失敗の理由（`error.message`）を表示し，コンパスは表示しない．`campass delete` で削除して作り直すことを案内する．
* `campass show <map_id> <node_id>` は `GET /api/maps/:mapId/nodes/:nodeId` の詳細と，`GET /api/nodes/:id/sub_nodes` のサブノードを同じ形式で表示する（F-007）．
* `campass start <map_id> <node_id>` / `campass done <map_id> <node_id>` は `PATCH /api/maps/:mapId/nodes/:nodeId/progress` を呼び，更新後のコンパスを表示する．`origin_completion_suggestion` が返った場合は，元ノードを `campass done` で完了にできることを案内する．
* `campass delete <map_id>` は `GET /api/maps/:id/deletion_preview` の内容を表示し，`y/N` で確認してから `DELETE /api/maps/:id` を呼ぶ．Web と同じく，生成中のマップには「作成中です．削除すると作成も止まります」を添える．

#### 4.5.6 マップ生成のストリーミング受信

* SSE のレスポンスを `bufio.Scanner` で1行ずつ読み，空行までの `data:` 行をつなげて1イベントとし，JSON としてデコードする．`event:` 行のイベント名で処理を分岐する（形式は 4.3.1）．`node` は1イベントが1ノードに対応するため（4.3.2），デコードできたらすぐに表示する．
* `bufio.Scanner` は既定で1行64KBまでしか読めないため，`summary` の長いノードに備えて上限を広げる．
* `done` を受け取ったら受信を終えて `GET /api/maps/:id` に進む．`error` を受け取ったら `code` と `message` を表示し，`campass delete` で削除して作り直せることを案内して終了する．`deleted` を受け取ったら「マップが削除されました」と1行表示して終了する．CLI で表示中に `deleted` が届くのは，常に別の場所（Web や別のターミナル）で削除されたときである．
* つなぎ直すたびに保存済みのノードがもう一度届くため（4.3.1），表示済みのノード ID は表示しない．
* 終端イベントを受け取らずに接続が切れた場合は，生成が終わったとはみなさず，生成は続いていることと `campass map <map_id>` で確認できることを表示して終了する．
* `:` で始まるコメント行は無視する．未知のイベント名は，エラーにせず読み飛ばす．
* JSON としてデコードできないイベントは，黙って捨てずにエラーとして表示する．

#### 4.5.7 ノードの編集（F-018）

Web と同じ操作（4.2.10）を，ID を指定するサブコマンドで行う．ID は `campass map` と `campass show` に `#501` の形で表示している．グラフの編集は ID で1行に書けるため，対話形式にはしない．

```
campass node add    <map_id> --title "..." [--summary "..."] [--new]   # メインノードの追加（新規）
campass node add    <map_id> --node <node_id>                         # 既存ノードを置く
campass node edit   <map_id> <node_id> [--title "..."] [--summary "..."]
campass node remove <map_id> <node_id>
campass path add    <map_id> <from_id> <to_id>
campass path remove <map_id> <from_id> <to_id>
campass sub add     <map_id> <node_id> (--title "..." [--summary "..."] [--new] | --node <node_id>)
campass sub remove  <map_id> <node_id> <sub_node_id>
campass sub path add|remove <map_id> <node_id> <from_id> <to_id>
campass importance  <map_id> <node_id> high|mid|low
```

* ノードに関わる操作（`node edit`，`sub …`）も `<map_id>` を取る．API がどのマップから操作したかを必要とするためである（4.2.10）．
* `node add` / `sub add` を `--title` で実行したときは，`GET /api/nodes?q=` で既存ノードを探す．一致があれば番号付きの一覧（最後に「新しく作る」）を出して選ばせ，一致がなければそのまま新しく作る．選べないノードと「中にもある:」の注記は Web と同じく示す．`--new` を付けたときは提案を出さずに新しく作り，スクリプトから使えるようにする．
* `409 confirmation_required` が返ったら，影響するマップと削除される進捗のあるノードを表示し，`campass delete` と同じく `y/N` で確認してから `confirmed=true` で送り直す．確認を飛ばすオプション（`--yes` 等）は設けない．
* `422 cycle` などのエラーは，`message` を表示して終了する．
* 成功したら，マップに関わる操作は `campass map` と同じ形でマップとコンパスを，ノードに関わる操作は `campass show` と同じ形でノードを表示する．

#### 4.5.8 CLI の配布

**ビルドとリリース**

* タグ `cli/vX.Y.Z` を push すると，GitHub Actions で GoReleaser が動き，GitHub Releases にリリースを作る．
* バージョンはセマンティックバージョニングとする．最初は `cli/v0.1.0` とし，API が固まるまでは `0.x` とする．タグに `cli/` を付けるのは，同じリポジトリのほかの部分（`backend/`，`frontend/`）のタグと分けるためと，サブディレクトリにある Go モジュールのタグの決まり（モジュールのディレクトリ名を前に付ける）に合わせるためである．
* 対象は Linux / macOS / Windows × amd64 / arm64 の6つとする．Linux と macOS は `.tar.gz`，Windows は `.zip` にまとめ，`SHA256SUMS` を添付する．
* `-ldflags -X` で，バージョンと本番の API の URL を埋め込む．URL は GitHub Actions のリポジトリ変数から取る（秘密の値ではないため，シークレットにはしない）．
* 実装時に確かめること：GoReleaser の無料版で `cli/` の付いたタグを扱えるか．扱えなければ，Actions の中でタグを整形してから GoReleaser に渡す．

**配布**

* GitHub Releases：上の6つのアーカイブと `SHA256SUMS`．
* `go install github.com/ryuma-1/Campass/cli/cmd/campass@latest`．
* Homebrew：公開リポジトリ `ryuma-1/homebrew-tap` に GoReleaser が Formula を書き込む（書き込み用のトークンは Actions のシークレットに置く）．`brew install ryuma-1/tap/campass` で入れる．
* deb / rpm：GoReleaser（nfpm）で作って Releases に添付するだけとし，apt / dnf のリポジトリは作らない．
* Windows は `.zip` と `go install` だけとする．
* Homebrew と deb / rpm には，`campass completion` で出力した補完スクリプトを同梱する．

**署名**

* 実行ファイルには署名しない．macOS の Gatekeeper（`xattr -d com.apple.quarantine <実行ファイル>` か，システム設定から許可する）と Windows の SmartScreen（「詳細情報」→「実行」）の警告を回避する手順をリリースノートに載せる．
* 実装時に確かめること：Homebrew で入れたときに macOS の警告が出るか．

#### 4.5.9 未決事項

CLI に関わる未決事項は 9章にまとめる（CLI とバックエンドの互換性）．トークンの有効期限は 4.5.4 で決めた．生成中の中断（Ctrl+C）の扱いは 4.2.9 と 4.5.3 で，配布方法は 4.5.8 で決めた．

### 4.6 Web の認証（F-019）

ブラウザのログインは Google と GitHub のアカウントで行い，ログイン後は DB に置く Cookie セッションで認証する．CLI のトークン（4.5.4）とは別の仕組みとし，バックエンドはどちらでもユーザーを特定できるようにする．方式を選んだ理由は 5.11 に示す．

**ログインと利用者**

* ログインは Google と GitHub のアカウントだけで行う．Campass はパスワードを持たない（`users` に `password_digest` はない）．
* 登録画面はない．初めてログインしたときにユーザーを作り，`users.name` にはプロフィールの名前（なければメールアドレスの @ の前）を入れる．
* ログインの判定は `user_identities` の `provider` + `provider_uid` で行う．メールアドレスは Google / GitHub 側で変わることがあるためである．
* Google / GitHub が「確認済み」とするメールアドレスだけを使う．Google は `email_verified` が `true` のメールアドレス，GitHub はメールアドレス一覧（スコープ `user:email`）のうち `verified` のものとする（既存のユーザーとまとめるときはそのどれかが一致すればよく，ユーザーを作るときは `primary` のものを優先する）．確認済みのメールアドレスがないアカウントではログインさせず，S-05 に「確認済みのメールアドレスが必要です」と表示する．
* ログインのたびに次の順でユーザーを決める．
  1. `(provider, provider_uid)` の `user_identities` があれば，そのユーザーとする．
  2. なければ，確認済みのメールアドレスのどれかが既存の `users.email` と一致するユーザーに，`user_identities` を1行足してまとめる．Google と GitHub で同じメールアドレスを使っていれば，どちらでログインしても同じユーザーになる．
  3. それもなければ，ユーザーと `user_identities` を作る．
* 確認していないメールアドレスでまとめないのは，乗っ取りを防ぐためである．他人のメールアドレスを確認せずに登録できるサービスでそのアドレスを名乗れば，まとめた先のユーザー（他人のマップとノード）にログインできてしまう．

**セッション**

* Cookie には，ランダムな長いセッショントークン（例：`SecureRandom.urlsafe_base64(32)`）だけを入れる．DB の `web_sessions.token_digest` にはその SHA-256 ハッシュを保存し，平文は保存しない（`api_tokens` と同じ考え方．DB が漏れてもセッションは使えない）．
* 有効期限は最後に使ってから30日とする．使うと `last_used_at` と `expires_at` を更新して延ばす（スライド式）．更新は CLI のトークン（4.5.4）と同じく1日に1回までとし，`last_used_at` が1日以上前のときだけ書き込む．絶対的な上限は設けない．期限切れのセッションは使わず，`401` を返す．期限切れの行は消さない（掃除は 9章）．
* ログアウト（`DELETE /api/session`）は，その端末の `web_sessions` の行を消し，Cookie を消す．同じユーザーの他の端末のセッションと CLI のトークンには触れない．
* バックエンドは「Cookie セッション または Bearer トークン（CLI，4.5.4）」でユーザーを特定する．`Authorization` ヘッダーがあるリクエストは Bearer トークンだけで判定し，Cookie は見ない．
* omniauth がログインの途中で一時的に使う値（`state`，Google の PKCE の値，`return_to`）は，Rails 標準の Cookie セッション（暗号化された Cookie）に置く．Rails の API モードでは外れているセッションと Cookie のミドルウェア（`ActionDispatch::Cookies`，`ActionDispatch::Session::CookieStore`）を戻し，`ActionController::API` に含まれない `ActionController::Cookies` と `ActionController::RequestForgeryProtection` もコントローラーに読み込む．ログインが済んだら，この一時的なセッションはリセットする（セッション固定の防止）．ログインの状態そのものは，この Cookie ではなく `web_sessions` で持つ．

**配信とセキュリティ**

* フロントエンドとバックエンドは，同じ親ドメインのサブドメインで配信する（例：`app.campass.example.com` / `api.campass.example.com`）．別オリジンだが同じサイトなので，`SameSite=Lax` の Cookie が送られる．まったく別のドメインには置かない（バックエンドの Cookie がサードパーティ Cookie になり，送られないブラウザがあるため）．
* フロントエンドのオリジンは環境変数 `FRONTEND_ORIGIN` で持つ．
* **Cookie の属性**: ログインの Cookie と Rails 標準のセッションの Cookie は，`Domain` 属性を付けず `api.` にだけ付く．`HttpOnly`・`Secure`・`SameSite=Lax` とする．`Secure` は開発環境（`http://localhost`）でだけ外す．`Strict` にしないのは，Google / GitHub から `api.` のコールバックへ戻る遷移で Rails 標準のセッションの Cookie（`state`）が送られる必要があるためである．
* **CORS**: `rack-cors` で，`FRONTEND_ORIGIN` だけを Cookie つき（`credentials`）で許可する．許可するメソッドは GET / POST / PATCH / DELETE，ヘッダーは `Content-Type` と `X-CSRF-Token` とする．
* **CSRF**: Rails 標準の CSRF トークンを `GET /api/session` のレスポンス本文で返す（4.3.1）．SPA は書き込み系（POST / PATCH / DELETE）のリクエストに `X-CSRF-Token` を付ける．加えて，書き込み系では `Origin` ヘッダーが `FRONTEND_ORIGIN` と一致するかを確かめる．どちらかが合わなければ `403`（`invalid_csrf`）を返す．Bearer トークンのリクエストは CSRF の検査の対象外とする（ブラウザが他のサイトから勝手に付けることはできないため）．認証なしの CLI のログイン要求の作成と受け取り（`POST /api/auth/cli_login_requests`，`…/token`，4.5.4）も Cookie を使わないため対象外とする．
* **クライアント**: SPA は `fetch` に `credentials: 'include'` を付け，SSE は `new EventSource(url, { withCredentials: true })` でつなぐ（4.3.1）．
* **開発環境**: React（`localhost:5173`）と Rails（`localhost:3000`）を別オリジンのまま動かし，`FRONTEND_ORIGIN=http://localhost:5173` として本番と同じ CORS の設定で開発する．ポートが違ってもサイトは同じなので，`SameSite=Lax` の Cookie は送られる．
* Google / GitHub のクライアントID・シークレット（`GOOGLE_CLIENT_ID`，`GOOGLE_CLIENT_SECRET`，`GITHUB_CLIENT_ID`，`GITHUB_CLIENT_SECRET`）は，LLM APIのキーと同じくバックエンドの環境変数でだけ持ち，フロントエンドには渡さない．

**ログインの流れ**

未ログインで `/cli/activate` を開いた場合を例にする．

1. SPA が `GET /api/session` を呼び，`401` なら S-05 `/login?return_to=/cli/activate` に移る．
2. 「Google でログイン」「GitHub でログイン」は，`api.` の `POST /api/auth/google` / `POST /api/auth/github` への，CSRF トークン付きのフォーム送信とする（`omniauth-rails_csrf_protection`．GET でログインを始められると，他のサイトから勝手にログインを始めさせられるため）．フォームには `return_to` を含め，バックエンドは一時的なセッションに覚えて Google / GitHub のログイン画面へ転送する．
3. Google / GitHub でログインすると，`api.` の `GET /api/auth/:provider/callback` に戻る．`state` を確かめ，上の「ログインと利用者」の規則でユーザーを探すか作り，`web_sessions` に1行足してログインの Cookie を付ける．Google では PKCE を有効にする．
4. `FRONTEND_ORIGIN` + `return_to` へ転送する．`return_to` は `/` で始まり `//` で始まらないパスだけを受け付け，それ以外（絶対 URL，`//evil.example.com` など）や指定なしは `/maps` にする．転送先のオリジンは利用者の入力から決めず，常に `FRONTEND_ORIGIN` とする（オープンリダイレクトの防止）．
5. ログインに失敗した場合（確認済みのメールアドレスがない，`state` が合わない，Google / GitHub で拒否された）は，`FRONTEND_ORIGIN` + `/login?error=:code` へ転送し，S-05 に理由を表示する．`code` は `email_not_verified`（「確認済みのメールアドレスが必要です」）と `auth_failed` とする．

* omniauth の既定のパス（`/auth/:provider`）は，`path_prefix` を `/api/auth` にして上の API に合わせる．
* GitHub はスコープ `user:email` を指定し，メールアドレス一覧から確認済みのものを取る．

## 5. 検討した代替案（Alternatives Considered）

### 5.1 グラフ表現：グラフDB vs リレーショナルDB（ノード・エッジ方式）

* **案A（採用）**: MySQL 上にノード・エッジテーブルを設けてグラフを表現する．
  * 利点: 既存の技術スタック（MySQL）をそのまま使え，スモールスタート（100〜1,000 DAU）の規模では十分な性能が出せる．マップ単位でのトランザクション管理も容易．
  * 欠点: 深い階層の依存関係探索（多段階のJOIN）はグラフDBほど高速ではない．
* **案B（不採用）**: Neo4j 等の専用グラフDBを導入する．
  * 利点: 依存関係の探索・パス検索がネイティブに高速．
  * 欠点: ReqDef 6章で技術スタックがMySQLと明記されており，インフラ構成が複雑化する．初期リリース規模（ReqDef 5.2）に対して過剰投資であると判断し，不採用とした．ただしノード数・道の数が大幅に増加する場合は再検討の余地を残す．

### 5.2 マップ生成方式：一括生成 vs ストリーミング生成

* **案A（採用）**: LLMにノード単位でストリーミング生成させ，逐次DB保存・逐次UI描画する．
  * 利点: ReqDef 5.2 が要求する体感待ち時間の最小化を満たす．生成途中でユーザーが最初の一歩を読み始められる．
  * 欠点: ノード単位でのJSONパース処理，および途中でエラーが起きた場合のロールバック処理が複雑になる．ロールバックは，ジョブが保存したノードだけを SSE が DB から読んで送り，途中で失敗したマップは `failed` として残す（削除して作り直す）ことで不要にした（4.2.9，ADR 0004）．
* **案B（不採用）**: マップ全体を一括生成してから一度にレスポンスする．
  * 利点: 実装がシンプルで，JSON全体の整合性検証がしやすい．
  * 欠点: 生成に数十秒かかる間ユーザーが何も見えない状態になり，ReqDef 5.2 の要件を満たさない．
* **応答時間の実測**（プロトタイプ，モデル `gemini-3.1-flash-lite`）: スタンダードは全体で6〜10秒，ディープは36〜46秒かかった．ストリーミングなら，最初のノードは4〜12秒で届く．ディープを一括生成すると40秒前後何も見えないため，ストリーミングが必要という判断を裏づける．

### 5.3 一本道変換のタイミング：生成直後変換 vs 表示時変換（v0.5.0 で廃止）

> v0.5.0 で一本道ビューと `display_order` を廃止したため，本検討は不要となった．経緯の記録として残す．

* **案A（採用）**: シラバス生成直後にバックエンドでリニア変換を行い，`display_order` として永続化する．
  * 利点: フロントエンドは常に確定済みの順序を受け取ればよく，表示ロジックがシンプルになる．同一シラバスを複数回開いても順序が一貫する．
* **案B（不採用）**: グラフ構造のみを保存し，表示の都度フロントエンドでトポロジカルソートする．
  * 利点: バックエンドの実装がシンプル．
  * 欠点: 同順位ノードの順序がリクエストごとに揺れる可能性があり，「一本道」という体験の一貫性を損なう．また，進捗管理（F-010）とノードの並び順を紐付けにくい．

### 5.4 クロスノートブックリンクの関連度判定：Embedding類似度 vs 別方式（v0.9.0 で廃止）

> v0.9.0 でノードをマップ間で共有する方式（5.7，ADR 0003）に変えたため，本検討は不要となった．なお，当時不採用とした案B（既存ノード一覧をLLMに渡す）が，現在の 4.2.4 の方式の基になっている．経緯の記録として残す．


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
  * 利点: 単一の実行ファイルとして各OS向けに配布でき，利用者が実行環境を用意する必要がない（ReqDef 5.1）．HTTP クライアントと SSE の受信を標準ライブラリだけで書ける．コマンドの解析には cobra があり（下記），依存を cobra だけに抑えられる（4.5.1）．
  * 欠点: フロントエンド・バックエンドと型定義を共有できず，API 仕様とのずれをコンパイル時に検出できない．
* **案B（不採用）**: TypeScript（Node.js）で実装する．
  * 利点: フロントエンドと API の型定義や API 通信層を共有できる．
  * 欠点: 利用者に Node.js が必要になり，単一の実行ファイルにするには追加のツールが要る．
* **案C（不採用）**: Ruby で実装する．
  * 利点: バックエンドと言語を揃えられる．
  * 欠点: 利用者に Ruby の実行環境が必要になる．

Go の中でのコマンドの解析は，次のように比べた．

* **案A（採用）**: `github.com/spf13/cobra` を使う．
  * 利点: サブコマンドが多く（`node add`，`sub path add` のように入れ子にもなる．4.5.7），その定義・ヘルプ・引数の検査をまとめて書ける．bash / zsh / fish / PowerShell の補完を生成でき（`campass completion`），Homebrew と deb / rpm に同梱できる（4.5.8）．
  * 欠点: 外部パッケージへの依存が増え（cobra と，cobra が使う `spf13/pflag`・`inconshreveable/mousetrap`），その更新・脆弱性対応が要る．
* **案B（不採用）**: 標準ライブラリの `flag` で書く．
  * 利点: 外部パッケージに依存しない．
  * 欠点: サブコマンドの振り分け，入れ子のサブコマンド，ヘルプ，補完を自分で書くことになり，コマンドが増えるほどコードと誤りが増える．

### 5.6 CLI の認証：トークン方式 vs Cookie セッション

* **案A（採用）**: ログイン時に発行したトークンを `Authorization: Bearer` ヘッダーで送る（4.5.4）．
  * 利点: CLI から扱いやすく，トークン単位で失効できる．DBにはハッシュのみを保存するため，DBが漏えいしてもトークンは使えない．
  * 欠点: トークン発行・失効の API と `api_tokens` テーブルが追加で必要になる．
* **案B（不採用）**: フロントエンドと同じ Cookie セッションを CLI でも使う．
  * 利点: バックエンドの認証の仕組みを1つにできる．
  * 欠点: CLI 側で Cookie と CSRF 対策を扱う必要があり，実装が複雑になる．

トークンを受け取るまでのログインの方法は 5.12 で比べる．

### 5.7 マップ間の関係：ノードの共有 vs リンク（ADR 0003）

* **案A（採用）**: ノードをユーザーの持ち物とし，マップ生成時に既存ノードをLLMに伝えて再利用させる．内容と進捗は共有し，道・メインノードかどうか・重要度はマップごとに持つ．
  * 利点: 同じ内容を2回学ばずに済み，進捗がマップ間で自然に揃う．Embedding API と提案・承認の流れが不要になる．
  * 欠点: プロンプトに既存ノードを含めるため，ノード数が増えるとプロンプトが長くなる（9章）．マップが自分のノードを持たなくなるため，削除や現在地の扱いが複雑になる（4.1.2，4.2.8）．
* **案B（不採用）**: ノードはマップごとに別々に持ち，似たノードを Embedding で検出して提案し，承認されたらリンクする（v0.8.0 までの設計）．
  * 欠点: 同じ内容を別々に学習・管理することになり，リンクは進捗を運ばない．
* **案C（不採用）**: 生成中に既存ノードの再利用ごとにユーザーの承認を求める．
  * 欠点: マップが育っていく様子を眺める体験が途切れる．
* **案D（不採用）**: 生成後に Embedding で重複を検出して取り除く．
  * 欠点: 取り除いたノードへの道が切れ，そのノードがすでに SSE で送られている可能性がある．

### 5.8 任意のテーマの扱い：サブクエスト vs 寄り道（ADR 0002）

* **案A（採用）**: ゴールとの関係が薄いテーマは，ノードではなく寄り道（新しいマップの提案）とする．
  * 利点: マップのノードはすべてゴールに必要なものになり，進捗・コンパス・ゴール到達の計算で例外を作らずに済む．
* **案B（不採用）**: サブクエスト（`route_type = sub`）としてマップの中のノードに残し，脇道として描く（v0.8.0 までの設計）．
  * 欠点: ノードに関するあらゆる計算で，サブクエストを除外する特別扱いが必要になる．

### 5.9 現在地：マップごとに保存 vs 進捗の履歴から導出（ADR 0005）

v0.11.1 までは案A を採用していた．ノードの編集（F-018）でメインノードを外せるようになり，外したノードが現在地だったときに「前の現在地」へ戻す必要が出たため，案C に切り替えた．

* **案A（不採用）**: 現在地をマップごとに保存し（`maps.current_node_id`），そのマップでメインノードを開始・完了したときに更新する．
  * 利点: 実装が単純である．
  * 欠点: 1つの値しか持たないため，現在地のノードを外したり未着手に戻したりしたとき，前の現在地が分からない．
* **案B（不採用）**: マップごとの位置づけ（`map_nodes`）に「このマップで最後に開始・完了した日時」を持たせ，その最大のノードを現在地とする．
  * 利点: 外すと日時も消えるため，前の現在地に戻る．
  * 欠点: 日時を上書きするため過去の出来事が残らず，将来，学習の履歴を見せることができない．
* **案C（採用）**: マップごとに進捗の更新の記録（開始・完了・未着手に戻す）を追記し（`map_progress_events`），今も置かれているメインノードの最新の記録から現在地を導出する（4.2.8）．
  * 利点: 外したり未着手に戻したりすると，自然に前の現在地に戻る．記録を消さないため，将来の履歴表示に使える．他のマップでの更新は記録しないため，案A と同じく他のマップの現在地は動かない．
  * 欠点: 記録が増え続ける．現在地を求めるたびに集計が必要になる（マップごとの索引 `(map_id, id)` で対応する）．

### 5.10 接続が切れたときの生成：続ける vs 止める（ADR 0004）

* **案A（採用）**: 生成をリクエストから切り離したバックグラウンドジョブで行い，SSE が切れても最後まで続ける．SSE は DB から保存済みのノードを読んで送り，何度でもつなぎ直せる．
  * 利点: 生成中に S-03 を再読み込みしたり離れたりするのは普通に起きるが，それで生成が壊れない．保存したノードと送ったノードが常に一致する．
  * 欠点: ジョブ，SSE のつなぎ直し，ジョブが消えたことの検知（ハートビート）が必要になる．
* **案B（不採用）**: SSE が切れたら生成も止める（Rails の `ActionController::Live` の既定の動き）．
  * 利点: 実装が最も単純．
  * 欠点: 再読み込みやタブの誤操作でも生成が中断される．
* **つなぎ直しの方式**: 保存済みのノードを全部送り直し，クライアントが ID で上書きする方式を採用した．`GET /api/maps/:id` のポーリングは，ノードが1つずつ現れる表示（F-009）を失うため不採用．`Last-Event-ID` による途中からの再開は，再読み込みで結局すべてを取り直すことになり，イベント ID の管理が増えるだけのため不採用．
* **ジョブの実行方式**: プロトタイプ（`prototype/q4-generation-job` ブランチ）で比べ，ActiveJob の `:async` アダプタを採用した．
  * `Thread.new`：`:async` と同じくプロセス内で動くが，例外の記録や DB 接続の返却を自分で書く必要がある．
  * Solid Queue：ジョブが DB に残り再起動後に再実行できるが，gem・ワーカープロセス・キュー用テーブルが増える．LLM のストリームは途中から再開できないため，再実行しても最初からやり直すことになり，すでに送ったノードと食い違う．得られるのは「失敗に早く気づける」ことだけで，それはハートビートで足りる．
  * 必要になれば，`queue_adapter` の設定を変えて移行する．

### 5.11 Web の認証

ブラウザのログインについて，次の5点を比べた（4.6）．

**(1) セッションの持ち方：Cookie セッション vs トークン方式**

* **案A（採用）**: ランダムなセッショントークンを `HttpOnly` の Cookie に入れる．
  * 利点: JavaScript からトークンを読めないため，XSS があってもトークンそのものは盗まれない．`EventSource` はヘッダーを付けられないが，Cookie なら SSE もそのまま認証できる．
  * 欠点: Cookie はブラウザが自動で送るため，CSRF の対策（CSRF トークンと `Origin` の確認）と CORS の設定が要る．
* **案B（不採用）**: CLI と同じトークンを SPA が保存し，`Authorization: Bearer` で送る．
  * 利点: CSRF の対策が要らず，バックエンドの認証の仕組みを CLI と1つにできる．
  * 欠点: トークンを `localStorage` などに置くと，XSS で読み出される．SSE は `EventSource` を使えず，`fetch` でストリームを読む処理を自分で書くことになる．

**(2) ログイン方法：Google / GitHub だけ vs パスワードも残す**

* **案A（採用）**: Google と GitHub のアカウントだけでログインする．
  * 利点: パスワードを保存しないため，パスワードの漏えい・使い回し・リセットの仕組みを考えなくてよい．登録画面が要らない．Web でログインできれば，CLI も Web のログインに乗せられる．
  * 欠点: どちらのアカウントも持たない人は使えない．Google / GitHub が止まるとログインできない．
* **案B（不採用）**: メールアドレスとパスワードのログインも残す．
  * 利点: 外部のアカウントを持たない人も使える．
  * 欠点: パスワードのハッシュ，リセットのメール送信，メールアドレスの確認が要り，実装と運用の負担が大きい．外部アカウントとまとめるときの確認も複雑になる．

**(3) 配信の形：別オリジン・同じ親ドメイン vs 同じオリジン vs まったく別のドメイン**

* **案A（採用）**: `app.` と `api.` のように，同じ親ドメインのサブドメインに分ける．
  * 利点: フロントエンドとバックエンドを別々に配信・デプロイできる．同じサイトなので `SameSite=Lax` の Cookie が送られ，サードパーティ Cookie の制限を受けない．開発環境（`localhost:5173` と `localhost:3000`）も同じ形になる．
  * 欠点: CORS の設定（`credentials` つき）と，書き込みの `Origin` の確認が要る．
* **案B（不採用）**: 同じオリジンにまとめる（Rails が SPA も配信する，またはリバースプロキシで `/api` を振り分ける）．
  * 利点: CORS が要らず，Cookie の扱いが最も単純．
  * 欠点: 配信の仕組みが1つにまとまり，フロントエンドだけを CDN などで配信しにくい．開発環境でもプロキシの設定が要る．
* **案C（不採用）**: まったく別のドメインに置く．
  * 利点: 配信先を自由に選べる．
  * 欠点: バックエンドの Cookie がサードパーティ Cookie になり，送られないブラウザがある．

**(4) OAuth の実装：omniauth vs 自前で書く**

* **案A（採用）**: `omniauth`，`omniauth-google-oauth2`，`omniauth-github` と `omniauth-rails_csrf_protection` を使う．
  * 利点: `state` の確認，PKCE，トークンの交換，プロフィールの取得を広く使われた実装に任せられる．Rails で標準的な方法で，テスト用のモックもある．
  * 欠点: omniauth 関連の gem が4つ増える．omniauth はセッションを使うため，API モードで外したミドルウェアを戻す必要がある．
* **案B（不採用）**: OAuth 2.0 の処理を標準ライブラリ（`Net::HTTP`）で自前で書く．
  * 利点: 依存が増えない．
  * 欠点: `state` や PKCE の確認など，誤るとそのまま脆弱性になる処理を自分で書いて保守することになる．

**(5) セッションの保存先：DB の自前テーブル vs `activerecord-session_store` vs `api_tokens` とまとめる**

* **案A（採用）**: `web_sessions` を作り，トークンのハッシュ，有効期限，最終利用時刻を持つ．
  * 利点: ハッシュだけを保存するため，DB が漏れてもセッションは使えない．その端末だけのログアウト，30日のスライド式の期限を素直に書ける．将来の「ログイン中の端末の一覧」にも使える．gem が要らない．
  * 欠点: セッションの発行・確認・延長を自分で書く．
* **案B（不採用）**: `activerecord-session_store` で Rails のセッションを DB に置く．
  * 利点: Rails のセッションの仕組みをそのまま使える．
  * 欠点: gem が増える．セッションの中身をそのまま保存し，ユーザーとの対応やスライド式の期限を扱うには結局手を入れる必要がある．
* **案C（不採用）**: `api_tokens` にまとめ，種類を表すカラムで Web と CLI を分ける．
  * 利点: テーブルとトークンを確かめる処理を1つにできる．
  * 欠点: Web のセッションと CLI のトークンは，発行のしかた（Cookie か，レスポンスで渡すか），CSRF の検査の有無，`user_agent` と `name` のように持つ情報が違い，条件分岐が増える．

### 5.12 CLI のログイン：パスワード入力 vs ローカルへのリダイレクト vs デバイスコード

Web のログインを Google / GitHub だけにしてパスワードを廃止したため（4.6），`campass login` がトークンを受け取る方法を比べた（4.5.4）．

* **案A（不採用）**: CLI でメールアドレスとパスワードを入力させる（v0.13.0 までの設計）．
  * 利点: ブラウザが要らず，ターミナルだけで済む．
  * 欠点: Campass はパスワードを持たないため，そもそも使えない．仮にパスワードを残しても，入力中に表示しないためのエコー制御を OS ごとに書く必要があり，標準ライブラリだけでは Windows を含めて扱いにくい．
* **案B（不採用）**: CLI が `localhost` で一時的な HTTP サーバーを立て，ブラウザでのログイン後にそこへリダイレクトさせてトークンを渡す．
  * 利点: 利用者はブラウザでログインするだけで，コードを打たなくてよい．
  * 欠点: CLI と同じマシンでブラウザを開く必要があり，SSH 先やコンテナの中では使えない．ポートの確保，リダイレクト先の検証，`state` の確認を CLI とバックエンドの両方で書く必要がある．
* **案C（採用）**: RFC 8628 のデバイスコード方式．CLI が表示したコードを，利用者がブラウザの S-04 に入力して許可する．
  * 利点: ブラウザは別のマシンでもよいため，SSH 先やコンテナの中でも使える．CLI はパスワードを扱わず，エコー制御が要らない．Web のログイン方法（Google / GitHub など）が変わっても CLI は変わらない．CLI 側は標準ライブラリ（`net/http`，`os/exec`，`os/signal`）だけで書ける．
  * 欠点: 利用者がコードを打つ手間がある．ログイン要求のテーブル（`cli_login_requests`），4つの API と照会の API，S-04 の画面が増える．
  * URL にコードを含めないのは，フィッシングを防ぐためである．含めると，攻撃者が自分の端末でログインを始め，そのリンクを利用者に踏ませて「許可」させれば，攻撃者の CLI が利用者のトークンを受け取れてしまう．利用者に自分のターミナルのコードを打たせることで，自分が始めたログインだけを許可させる．

## 6. 懸念事項（Caveats / Security / Privacy Concerns）

* **APIキーの秘匿化**: 外部LLM APIキーは必ずバックエンド（サーバーサイド）で管理し，フロントエンドへ絶対に露出させない．環境変数またはシークレットマネージャで管理し，リポジトリへのコミットを防ぐ仕組み（lint / pre-commit hook 等）を導入する（ReqDef 5.3）．
* **学習データへの利用**: ユーザーの自由記述ワーク（興味・ゴールの入力等）に個人情報や機密情報が含まれる可能性があるため，本番のサービスの API キーは入出力を学習に使わない契約のプランのものだけを使い，デプロイの手順で確かめる（ReqDef 5.3，4.3.2）．利用者が自分の API キーで送る分はこの約束の対象外とし，利用者とその会社との契約の規約に従うことを S-06 で示す（4.4）．
* **利用者の API キー（ReqDef F-020）**:
  * **暗号化**: `user_llm_credentials.api_key` は Rails 標準の Active Record Encryption で暗号化して保存する（gem を増やさない）．検索に使わないため，非決定的な暗号化とする．DB やバックアップが漏れても，暗号化の鍵がなければキーは読めない．
  * **鍵の管理**: Rails の3つの鍵（primary key，deterministic key，key derivation salt）を，環境変数 `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`，`ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY`，`ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` で渡す（値は `bin/rails db:encryption:init` で作る）．他の秘密と同じく `.env` からバックエンドにだけ渡し，DB とは別に保管する．鍵をなくすと，保存したキーは読めなくなる．その場合は復号に失敗した呼び出しを `user_api_key_invalid` とし（4.3.2），利用者に S-06 で設定し直してもらう．
  * **返さない・ログに出さない**: キーはどの API の応答にも含めない（会社，モデル，末尾4文字，確かめた日時だけを返す．4.3.1）．`config.filter_parameters` に `api_key` を足し，リクエストのログに出さない（Rails の既定の `_key` でも隠れるが，既定に頼らず明示する）．例外のメッセージ，ログ，エラーの応答にもキーを含めない．エラーの応答は「コード→文言」の対応表から作り，会社の応答の本文や例外のメッセージをそのまま返さない（4.3.1）．会社の API にはキーをヘッダーで渡し，URL に入れない（4.3.2）．キーはジョブの引数にも入れない（4.2.9）．
  * **フロントエンドとの接点**: キーがフロントエンドを通るのは，S-06 で利用者が入力して HTTPS で一度送るときだけである．フロントエンドは送った後にキーを状態や `localStorage` に残さない（4.4）．CLI からは設定できない．
* **Web のログイン**: Cookie は `HttpOnly`・`Secure`・`SameSite=Lax` とし，CSRF トークンと `Origin` の確認，`FRONTEND_ORIGIN` だけを許す CORS，`return_to` の制限でクロスサイトからの書き込みとオープンリダイレクトを防ぐ．確認していないメールアドレスではユーザーをまとめない（4.6）．
* **CLI のトークン管理**: CLI のトークンはユーザーの端末にファイルとして保存されるため，所有者のみ読み書きできる権限（0600）で保存し，有効期限を設ける．有効期限は最後に使ってから30日のスライド式で，絶対的な上限はない．使い続けている端末ではログインし直さずに済む一方，30日使わなかった端末のトークンは使えなくなる．`campass logout` で失効でき，DBにはハッシュのみを保存する（4.5.4）．
* **CLI のログイン**: `device_code` は DB にハッシュだけを保存し，トークンは CLI が受け取りに来たときに一度だけ渡す．`verification_uri` に `user_code` を含めず，S-04 で端末名と開始時刻を見せてから許可させることで，他人が始めたログインを許可させるフィッシングを防ぐ（4.5.4，5.12）．
* **プロンプトインジェクション対策**: ユーザーの自由入力がそのままLLMへのプロンプトに埋め込まれるため，システムプロンプトとユーザー入力を明確に分離し，構造化出力（JSON Schema／ツール呼び出し）を強制することで，意図しない指示の混入や出力形式の破壊を防ぐ．
* **マップのデータ保持**: マップ，ノードおよび学習ログはユーザーが自ら削除するか退会するまで永続保持する方針のため，退会時のデータ削除フロー（物理削除 or 論理削除）を別途明確にする必要がある（ReqDef 5.4）．
* **既存ノードの送信**: マップ生成のたびにユーザーの既存ノードのタイトルをLLMに送る．他ユーザーのノードは送らず，他のリクエストと同じく学習に使わない契約のプランのキーで送る（4.3.2）．利用者が自分のキーを設定していれば，他のリクエストと同じくそのキーで送る．
* **生成コンテンツの信頼性**: LLMが生成する学習ステップの内容やリンク先には誤り・幻覚（hallucination）が含まれ得る．本バージョンでは教材コンテンツ自体の制作を対象外としているため（Non Goals），外部リンクの生存確認や内容の正確性検証は当面ユーザーの判断に委ねる旨をUI上で明示する．

## 7. テスト方針（Test Plan）

* **マップ生成の構造検証**: LLMの出力に対し，JSON Schemaバリデーション，`map_paths`・`sub_node_paths`・`sub_nodes` の循環の検出，未知の参照の検出，ゴールへつながらないメインノード（孤立ノードを含む）の検出，メインノード数が `node_count_target` の範囲（4.2.2）の外にある出力の検出を自動テストで行う（4.2.4）．
* **既存ノードの再利用のテスト**: 既存ノードを再利用した出力から，`map_nodes`・`sub_nodes`・`progress_statuses` が正しく作られること（新しいノードを作らないこと，既存の進捗を引き継ぐこと，追加したサブノードが他のマップのドリルダウンにも現れること，他ユーザーのノードを参照できないこと）を検証する．元ノードからのマップで，生成したメインノードが元ノードのサブノードにも追加されることも確認する．
  * 再利用したノードの既存のサブノードを `sub_nodes` に書き直したフィクスチャで，`sub_nodes` と `sub_node_paths` が重複せず，出力に書かれなかった既存のサブノードと道も削除されないこと．
* **再生成のテスト**（4.2.4）: 検証エラーになる出力を返す LLM のスタブを使い，再生成のリクエストの会話に前回の出力と検証エラーが入ること，再試行が最大2回で止まることを検証する．
* **実際の LLM での手動確認**: 再利用したノードに中身全体を書かせる変更と，前回の出力と検証エラーを渡す再生成は，プロトタイプでも実際の Gemini では動かしていない．実装後に，実際の呼び出しで手動で確かめる（自動テストでは実際の LLM API を呼ばない）．
* **難易度パラメータのマッピングテスト**: 「ライト／スタンダード／ディープ」それぞれの選択が，意図した `max_depth`，`node_count_target` の範囲，サブノード数の目安（4.2.2）のプロンプト制約に正しく変換されるかを検証する．
* **ストリーミングのE2Eテスト**: 生成の途中で SSE 接続を切り，4.2.9・4.3.1・4.4 の振る舞いを確認する．LLM の応答は，固定のフィクスチャをノード単位で少しずつ返すスタブで置き換える．
  * 接続を切っても生成ジョブが止まらず，マップが最後には `ready` になること．
  * 同じ `GET /api/maps/:id/generation` でつなぎ直すと，保存済みのノードがすべて届いた後に続きのノードが届き，`done` で閉じること．
  * つなぎ直しで同じノードがもう一度届いても，UI に重複して描かれないこと（ノード ID による上書き）．
  * 途中までのノードが UI に正しく反映されること．ページを再読み込みして S-03 を開き直した場合も，保存済みのノードが描かれ，続きを受け取れること．
  * 生成が終わる（`done`）までコンパスが出ないこと．
  * ジョブが失敗したら `error` で閉じ，S-03 が失敗の表示（警告アイコンと理由，削除の案内．コンパスなし）に切り替わること．
  * 生成中のマップを別のタブで削除すると，S-03 が `deleted` を受け取り，残りのうち `updated_at` が最新のマップか，なければ S-02 へ移り，削除の知らせが出ること．
* **生成ジョブのテスト**（4.2.9，ADR 0004）: 生成ジョブをバックエンド単体で検証する．テストは Rails 標準の Minitest で書き（gem を増やさない），実際の LLM API は呼ばない．
  * 確かめる振る舞い:
    * ハートビート: `generating` のまま `generation_heartbeat_at` から上限（5分）を過ぎたマップが，SSE のループ，`GET /api/maps`，`GET /api/maps/:id` のどれでも `failed`（`timed_out`）になること．上限の直前（例：4分59秒）では `generating` のままであること．
    * 行ロック: ジョブのノード保存とマップの削除が同時に起きても，ノード1つ分の書き込みは全部入るか全部入らないかのどちらかになること．削除が先なら，ジョブは LLM のストリームを閉じ，`failed` にせず静かに終わり，共有のノードにサブノードを足さないこと．
    * 遅れたジョブ: `timed_out` で `failed` にされた後に動いたジョブが，`status` を確かめてノードを保存せずに止まること．
    * 例外: ジョブが例外で止まると，`status = failed` と `generation_error_code` が保存されること．例外のメッセージは DB にもレスポンスにも出ず，ログにだけ出ること．
    * 文言: SSE の `error` と REST の `error.message` が，同じ「コード→文言」の対応表（4.3.1）から作られること．
    * 生成中のマップの削除: 4.1.2 の削除の規則どおりに，他のマップに登場するノードと進捗が残り，どこにも登場しなくなったノードが削除されること．
  * 時刻: `ActiveSupport::Testing::TimeHelpers` の `travel_to` / `travel` で時刻を進め，実際には待たない．ハートビートの上限は設定値にし，テストはその値から上限の直前と直後の境目を作る（上限を変えてもテストを直さずに済むようにするため）．
  * 並行実行: 「たまたま同時に起きる」のを待つと結果が実行ごとに変わるため，順番を固定して再現する．
    1. ジョブを別スレッドで動かし，`maps` の行をロックした直後で一時停止させる．一時停止は Rails に入っている `concurrent-ruby` の `Concurrent::Event` などで作る．
    2. その間にメインスレッドでマップの削除を始め，ロックが解けるまで待たされることを確かめる．
    3. ジョブを再開させ，ノード1つ分がすべて保存されてから削除が進むことを確かめる．
    4. 逆の順（削除が先にロックを取り，ジョブが待たされる）も同じように作り，ジョブが保存せずに静かに終わることを確かめる．

    行ロックは DB の機能なので，このテストは実際の MySQL（Docker Compose の `db`）で動かす．また，2つのスレッドが別の接続で同じ行を見るため，このテストだけテストごとにトランザクションで巻き戻す機能（`use_transactional_tests`）を切り，テスト自身が作ったデータを終わったら片付ける．
  * LLM のスタブ: LLM のクライアントをジョブの外から差し替えられる形にし，テストでは次のことができる偽物を使う．フィクスチャはストリーミングの E2E テストと同じものを使い回す．
    * 固定のフィクスチャをノード単位で少しずつ返す．
    * 途中で例外を起こす．
    * `close` が呼ばれたかを記録する．
  * 必要な差し込み口: 生成ジョブには，LLM のクライアントを外から渡せることと，テストからだけ使える「`maps` の行をロックした直後」で一時停止させる差し込み口を用意する．ハートビートの上限は設定値にする．名前や形は実装に任せる．
* **コンパス決定ロジックのテスト**: 進捗状態の異なるマップ（未着手のみ・途中まで完了・`in_progress` が複数・サブノードのみ完了・全完了）と，分岐・合流を含むグラフに対して，4.2.8 の `current_node_id` / `candidates`（内容と並び順）/ `is_goal_reached` が期待どおりになるかを検証する．マップ間ノードについては，他のマップで学習中・完了のノード（既知ノード）が候補から外れ，道の手前として満たされること，このマップで学習中にしたノードは候補に残ること，`started_map_id` が NULL の学習中ノードが既知ノードにならないことを検証する．
* **現在地と進捗更新のテスト**: `PATCH /api/maps/:mapId/nodes/:nodeId/progress` で，そのマップの現在地だけが動き，同じノードが登場する他のマップの現在地は動かないこと，現在地のノードを未着手に戻すと前に開始・完了したノードが現在地になること，`started_map_id` が記録・解除されること，ゴール到達時に元ノードがあれば `origin_completion_suggestion` が返り，元ノードが自動で完了にならないことを確認する．
* **ノードの編集のテスト**（4.2.10）:
  * 道・サブノード・サブノード間の道が循環する編集が `422 cycle` で拒否され，何も保存されないこと．
  * 現在地のノードを外すと前に開始・完了したノードが現在地になり，外したノードを置き直しても古い記録が現在地に使われないこと．すべて外すとスタート地点に戻り，ゴール到達にならないこと．
  * メインノードを外すと道と寄り道が消え，どこにも残らなくなったノードだけが削除されること．他のマップのメインノードや，他のノードのサブノードとして残るものは削除されないこと．
  * 他のマップに反映される編集と，進捗のあるノードが削除される編集が，`confirmed` なしでは `409 confirmation_required` になり，何も変わらないこと．
  * `ready` 以外のマップでの編集が `409 map_not_ready` になること．他ユーザーのノードを置いたり編集したりできないこと．
  * 既存ノードの提案が自分のノードだけを返し，`already_main` と `inside` が正しいこと．
  * 元ノードから作ったマップでメインノードを追加・外すと，元ノードのサブノードも同じように変わること．
  * 2か所から同じノードを続けて編集すると，後から保存した内容が残り，`409` にならないこと（同時の編集）．
* **マップの `updated_at` のテスト**（4.1.2）: 生成でのノードの保存と `status` の変更，このマップからの進捗の更新と編集で，このマップの `updated_at` が更新されること．同じノードが登場する他のマップの `updated_at` は，共有のノードの編集，進捗の更新，再利用でのサブノードの追加，元ノードのサブノードの変更，マップの削除によるノードの削除のどれでも変わらないこと．`GET /api/maps` が `updated_at` の新しい順（同じなら `id` の大きい順）に返ること．
* **開いている S-03 の同期のテスト**（4.4）: API の応答は固定の JSON で置き換え，時刻は差し替えて実際に待たない．
  * `visibilitychange` で `visible` になったときと，`window` の `focus` のときに `GET /api/maps/:id` を取り直すこと．両方が2秒以内に続けて起きても1回だけ取り直すこと．それ以外のとき（定期的）には取り直さないこと．サイドバーの一覧も同じ判定ですぐに取得すること．
  * 取り直したマップとコンパスに置き換わり，視点と拡大率が変わらないこと．詳細パネルを開いていれば，そのノードの詳細も取り直すこと．
  * 選んでいたノードが外されていたら，詳細パネルが閉じ，`?node=` が消え，「このノードはマップから外されました」が出ること．
  * 保存していない入力があり，そのノードが別の場所で変わっていたら，入力が残り，「このノードは別の場所で変更されました」が出て，「入力を捨てて最新を表示」で最新に置き換わること．変わっていなければ何も出ないこと．
  * 取り直しが `404` なら，`updated_at` が最新のマップか S-02 へ移り，削除の知らせが出ること．
* **マップ削除のテスト**: 他のマップに登場するノードと進捗が残り，どこにも登場しなくなったノードが削除されること，`deletion_preview` がそのマップで学習中にしたノードを返すことを確認する．
* **セキュリティテスト**: APIキーがフロントエンドのレスポンス・ソースマップ等に含まれていないことのスキャン．学習に使わせないことは，リクエストではなく API のプランで守るため，テストではなくデプロイの手順で確かめる（4.3.2）．
* **Web の認証のテスト**（4.6）: Google / GitHub の応答は omniauth のテスト用の設定（モック）で置き換え，実際の Google / GitHub は呼ばない．
  * 初めてのログインでユーザーと `user_identities` が作られ，`users.name` にプロフィールの名前（なければメールアドレスの @ の前）が入ること．2回目以降は `provider` + `provider_uid` で同じユーザーになり，メールアドレスが変わっていても同じユーザーになること．
  * 確認済みのメールアドレスが既存の `users.email` と一致すれば同じユーザーにまとめ，新しいユーザーを作らないこと．確認済みのメールアドレスがなければログインさせず，ユーザーも作らないこと．
  * `return_to` が `/maps/123` ならそこへ，`//evil.example.com`，`https://evil.example.com/` のような絶対 URL，`/` で始まらない値，指定なしなら `/maps` へ転送されること．転送先のオリジンが常に `FRONTEND_ORIGIN` であること．
  * Cookie セッションの書き込みが，CSRF トークンなし・違うトークン・`Origin` 違いでは `403` で拒否され，何も変わらないこと．Bearer トークンのリクエストは CSRF トークンなしで通ること．
  * 最後に使ってから30日を過ぎたセッションは `401` になり，期限内に使うと期限が延びること．前回の更新から1日以内なら `last_used_at` と `expires_at` を書き込まないこと．
  * ログアウトでその端末のセッションだけが消え，同じユーザーの別の端末のセッションと CLI のトークンは使えること．
  * `FRONTEND_ORIGIN` 以外のオリジンからのリクエストに，CORS の許可（`Access-Control-Allow-Origin`）が返らないこと．
  * DB に保存されるのがセッショントークンのハッシュだけで，平文が残らないこと．
* **CLI のテスト**: Go 標準の `testing` と `net/http/httptest` で作ったテスト用サーバーに固定の JSON を返させ，CLI 単体で検証する（実際のバックエンド・LLM API は呼ばない）．SSE 受信については，1イベントが複数の `data:` 行に分かれる場合，途中で接続が切れる場合，デコードできないイベントが来る場合を検証する．マップの表示については，コンパス候補が API の並びのまま表示されることを検証する．ノードの編集については，`409 confirmation_required` で `y/N` の確認を出し，`y` のときだけ `confirmed=true` で送り直すこと，`--new` を付けると提案を出さないことを検証する．トークンファイルが 0600 で保存されることも確認する．
  * バージョンと接続先（4.5.1，4.5.2）については，`campass version` が埋め込んだバージョンを表示し，埋め込みがなければ `dev` と表示すること，すべてのリクエストに `User-Agent: campass-cli/<バージョン>` が付くこと，`CAMPASS_API_URL` があれば埋め込んだ既定の URL より優先されることを検証する．
  * ログイン（4.5.4）については，テスト用サーバーに `…/token` の応答を順に返させ，`authorization_pending` では `interval` ごとに受け取りを続けること，`slow_down` で間隔が5秒延びること，`access_denied` と `expired_token` でそれぞれの文言を表示して終わること，`200` でトークンを保存すること，待っている間の Ctrl+C で改行を出して終了コード 130 で終わることを検証する．待つ時間は差し替えられるようにし，テストで実際に待たない．ブラウザを開けなくても URL とコードが表示されることも確認する．
  * トークンの期限切れ（4.5.4）については，テスト用サーバーに `401` の `token_expired` と `invalid_token` を返させ，それぞれの文言を表示し，トークンファイルを消して終了コード 1 で終わること，`campass login` を始めない（`cli_login_requests` を呼ばない）ことを検証する．
* **CLI のログインのテスト**（バックエンド，4.3.1）: `…/token` が4つの状態と成功を条件どおりに返すこと，トークンが一度だけ返り2回目は `expired_token` になること，DB に `device_code` とトークンの平文が残らないこと，`approve` / `deny` / `lookup` が Web のログインなしや Bearer トークンでは `401`，期限切れや `pending` でない要求では `404` になることを検証する．
  * トークンの有効期限（4.5.4）については，時刻を差し替えて，発行時の `expires_at` が発行時刻 + 30日になること，使えば `last_used_at` と `expires_at` が延びること，前回の更新から1日以内なら書き込まないこと，30日使わないと `401` の `token_expired` になること，失効させたトークンと存在しないトークンは `401` の `invalid_token` になることを検証する．
* **利用者の API キーのテスト**（ReqDef F-020，4.3.1，4.3.2）: 会社の API はスタブで置き換え，実際の LLM API は呼ばない．
  * キーが含まれない: `GET` / `PUT` / `DELETE /api/llm_credential` の成功とエラーの応答，`POST /api/goal_suggestions` のエラー，`GET /api/maps` と `GET /api/maps/:id` の `error`，SSE の `error` のどれにも，保存したキーの平文が含まれないこと．DB の `api_key` の値が平文と違う（暗号化されている）こと．
  * ログに出ない: `PUT /api/llm_credential` のリクエストのログで `api_key` が隠れること（`filter_parameters`）．LLM の呼び出しが例外で失敗したときのログにもキーが出ないこと．
  * 確かめられないキーは保存されない: 「キーとモデルを確かめる」のスタブが無効なキー・一覧にないモデル・接続の失敗を返すと，それぞれ `422 api_key_invalid`，`422 model_not_available`，`502 llm_api_error` になり，行が作られず，既存の設定も変わらないこと．候補にない会社・モデルは，会社の API を呼ばずに `422 model_not_available` になること．Bearer トークンの `PUT` と `DELETE` は `401` になること．
  * 利用者のキーで呼ぶ: キーを設定した利用者のマップの生成とゴール候補の提案で，LLM のクライアントが利用者の会社・モデル・キーで作られること．スタブが無効・上限を返すと `user_api_key_invalid` / `user_api_key_quota_exceeded` で失敗し，サービスのキーで呼び直さないこと．保存したキーを復号できないときも `user_api_key_invalid` になり，サービスのキーに切り替えないこと．
  * 始まったときのキーで続く: 生成ジョブをノードの保存の間で一時停止させ（生成ジョブのテストの差し込み口），キーを変える・消してから再開すると，残りのノードも始まったときのキーで生成されること．
  * 削除するとサービスのキーに戻る: `DELETE /api/llm_credential` の後の呼び出しが，`LLM_PROVIDER` / `LLM_MODEL` とサービスのキーで作られること．
* **負荷テスト**: ReqDef 5.2 の想定同時接続数（通常100 DAU，ピーク1,000 DAU）を基準としたマップ生成APIの負荷試験．

## 8. 運用・段階的リリース計画

* 初期リリースはスモールスタート仕様（通常100 DAU／ピーク1,000 DAU）のインフラ構成とし，将来的なアクセス急増時はパブリッククラウド（AWS等）でのスケールアップ／スケールアウトを前提とした設計に留める（ReqDef 5.2）．
* プロンプトテンプレートはソースコードのデプロイサイクルと切り離し，無停止でのA/Bテスト・チューニングを可能にする（ReqDef 5.4）．
* リリース初期はコア体験として F-001〜F-003, F-011 に加え，マップ（グラフ可視化），コンパス（F-013），マップ間ノード（F-015），寄り道（F-006），ノードの編集（F-018）も優先実装の対象とする．これは1章で確定した「マップとコンパスで進む」という目的そのものに直結するためである．優先度「低」の機能（F-009 既知ノードからの道の演出，F-010 マイルストーン成果物提示，F-016 ノードの深掘り，F-017 ノードのマップ化）は後続フェーズで段階的に追加する．

## 9. オープンな論点（今後議論が必要な事項）

* **既存ノード一覧のプロンプト長**: マップ生成時にユーザーの全ノードをLLMに渡すため（4.2.4），ノード数が増えるとプロンプトが長くなりコスト・レイテンシが悪化する．ゴールと関係の近いノードだけを渡す絞り込み（Embedding による選別等）をいつ・どう導入するか．
* **同時生成時のサブノード重複**: 2つのマップを同時に生成し，同じ再利用ノードにサブノードを追加すると，重複したサブノードができ得る．初期リリースでは対処しない．
* **マップ間ノードの共有解除**: 再利用が誤っていた場合に，ノードの共有を解除する機能を設けるか．
* **F-003 の見直し**: 後のフェーズで F-016（もっと詳しく）と F-017（ノードのマップ化）が入った後，最初に難易度を選ばせる必要があるか．
* **F-016 / F-017 の詳細**: 「もっと詳しく」で追加するサブノードの生成方法と API，ノードのマップ化の API と UI．元ノードから作ったマップを編集したときに元ノードのサブノードも変える規則（4.2.10）も，ここで合わせて確定する．
* **再生成と保存済みのノード**: 再生成（最大2回，4.2.4）は，前回の出力と検証エラーを渡して作り直させる．しかし，ノードは1つずつ保存して SSE で送るため（4.2.9），ゴールへつながらないノードやメインノード数の範囲のように最後まで受けないと分からない検証エラー（循環なども，見つかった時点で前のノードは保存済み）では，作り直すと保存して送ったノードと食い違う．4.2.9 は同じマップでのやり直しをしないとしているため，いつ再生成できるか（最初のノードを保存する前だけにする，保存済みのノードを残して続きを作らせる，など）と，保存済みのノード・送った SSE の扱いを決める必要がある．プロトタイプは DB に保存せず，全体を受けてから検証したため，この点は確かめていない．
* **生成中のマップと共有の編集**: 編集は `ready` のマップからだけ行えるが，内容やサブノードは共有のため，同じノードを再利用している別のマップが生成中のことがある．ユーザーがサブノードを外して削除した直後に，生成ジョブがそのノードを参照すると，未知の参照（4.2.4）として生成が失敗し得る．初期リリースでどこまで対処するか．
* LLM生成コンテンツの品質担保（幻覚対策）について，将来的にファクトチェック機構やユーザーフィードバックによる品質改善ループを設けるか．
* **期限切れの行の掃除**: 期限切れの `api_tokens`・`web_sessions`・`cli_login_requests` の行は消さず，使えないとするだけにしている（4.5.4，4.6）．今の設計には定期実行の仕組みがないため，行が増え続ける．いつ・どう消すか．
* **同時の編集の衝突**: 2か所から同じノードやマップを編集すると，後から保存したほうが勝つ（4.2.10）．防ぐなら，版の番号（Rails 標準の `lock_version`）を持たせ，古い版から保存しようとしたら `409` で断る方法がある．ただし，ノードはマップ間で共有なので（ADR 0003），どの行の版を比べるか（ノード，サブノード，道，マップ）の扱いが複雑になる．1人で使うアプリで衝突はまれなため，初期リリースでは対処しない．
* **CLI とバックエンドの互換性**: API を変えたときに古い CLI をどう扱うか（`User-Agent` のバージョンで断るか）と，新しい版が出たことを利用者にどう知らせるか（4.5.1，4.5.8）．

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
| v0.8.0 | 2026/10/07 | シラバス生成 SSE のイベント形式を 4.3.1 に定義（`node` / `link_proposal` / `done` / `error`，エラーコード，終端の扱い，Embedding API 失敗時の扱い，レスポンス例）．リンク提案を `node` から独立したイベントとし，4.3.2，4.5.3，4.5.6，4.5.7 を整合．9章から解決済みの論点を削除 | 池田 琉俊 |
| v0.9.0 | 2026/10/08 | 用語を GLOSSARY.md に合わせて整理（ノートブック・学習マップ・シラバスを「マップ」，前提を「道」に改称）．ノードをユーザーの持ち物としてマップ間で共有する方式に変更し（ADR 0003），4.1 のテーブルを再設計（`maps`，`nodes`，`map_nodes`，`map_paths`，`sub_nodes`，`sub_node_paths`，`detours`，`progress_statuses.started_map_id`）．サブクエストを寄り道に変更（ADR 0002），`supplementary`，クロスノートブックリンク（4.2.7）と Embedding を廃止．4.2.4（既存ノードの再利用），4.2.8（既知ノード，マップごとの現在地），4.3（API・SSE），4.4（画面・URL・初回表示），4.5（CLI）を更新し，5.7〜5.9 を追加．9章から解決済みの論点を削除し，新たな論点を追加 | 池田 琉俊 |
| v0.10.0 | 2026/10/09 | 前提知識アセスメントを廃止（ReqDef F-004）．`assessment_questions` / `assessment_answers` と `map_nodes.skip_recommended` を削除し，4.2.3 を廃止．3.2，4.1，4.2.4，4.3.1（`POST /api/maps/:id/assessment` を削除），4.4，4.5.3，6章，8章を整合し，9章からアセスメントの論点を削除 | 池田 琉俊 |
| v0.11.0 | 2026/10/09 | 生成中に接続が切れた場合の扱いを決定（9章の論点を解決，ADR 0004）．生成をバックグラウンドジョブ（ActiveJob `:async`）にし，接続が切れても続ける 4.2.9 を追加．`maps` に `generation_error_code` と `generation_heartbeat_at` を追加し，生成中のマップの削除を 4.1.2 に追加．4.3.1 で `POST /api/maps` をマップの作成と生成の開始にまとめ，`POST /api/maps/:id/generation` を `GET /api/maps/:id/generation`（つなぎ直せる SSE）に，`POST /api/maps/:id/goal_suggestions` を `POST /api/goal_suggestions` に変更．SSE に `deleted` イベントとエラーコード `timed_out` を追加．4.3.2，4.4（生成の状態，失敗の表示，削除の知らせ方），4.5（Ctrl+C，`campass map` の生成中・失敗，`campass delete`），5.2 を整合し，5.10 を追加 | 池田 琉俊 |
| v0.11.1 | 2026/10/09 | 7章のストリーミングの E2E テスト方針を，生成中に接続が切れた場合の扱い（4.2.9，v0.11.0）に合わせて具体化（つなぎ直し，ID による重複の除去，再読み込み，失敗と削除の終端イベント） | 池田 琉俊 |
| v0.12.0 | 2026/10/09 | ノードの編集（ReqDef F-018）を追加し，4.2.10 を新設．現在地を `maps.current_node_id` から，マップごとの進捗の履歴（`map_progress_events`）による導出に変更し（ADR 0005），5.9 の採否を見直した．同じマップでメインノードが別のメインノードの中にも現れることを許すと明記（ADR 0006）．4.1，4.2.4，4.2.8（現在地，空のマップ），4.3.1（編集 API，`also_inside`，確認と循環のエラー），4.4，4.5（CLI の編集コマンドを 4.5.7 に追加し，未決事項を 4.5.8 へ），7〜9章を整合 | 池田 琉俊 |
| v0.12.1 | 2026/10/11 | リポジトリを `backend/`・`frontend/`・`cli/` に分けた構成（基本設計書 2.5）に合わせ，4.5.2 に `cli/` の置き場所と Docker Compose の `cli` サービスを追記 | 池田 琉俊 |
| v0.13.0 | 2026/10/11 | Web のログイン（ReqDef F-019）を決定し，4.6 Web の認証を新設（Google / GitHub でのログイン，DB に置く Cookie セッション，`app.` / `api.` の別オリジン，CSRF・CORS・`return_to` の制限）．4.1 で `users.password_digest` を削除し `user_identities` と `web_sessions` を追加．4.3.1 にログイン・セッションの API を追加し，ブラウザの SSE の認証を Cookie セッションに決定．4.4 に S-05 ログイン画面を追加．パスワードの廃止に合わせて 4.5.4 に注記し，5.11 を新設，6・7章に Web の認証を追加．9章からフロントエンドの認証方式を削除し，CLI のパスワード入力の論点を CLI のログイン方法に置き換えた | 池田 琉俊 |
| v0.14.0 | 2026/10/11 | CLI のログインをデバイスコード方式（ブラウザで許可）に決定．4.1 に `cli_login_requests` を追加し，4.3.1 で `POST /api/auth/tokens` を廃止して CLI のログイン要求の API（作成・受け取り・照会・許可・拒否）を追加．4.4 に S-04 CLI ログインの承認を追加し，4.5.4 を書き直し，4.6 で CSRF の検査の対象外に CLI のログイン要求の作成と受け取りを加えた．4.5.8 の未決事項を更新．5.12 を新設し，6・7章に CLI のログインを追加．9章から CLI のログイン方法を削除 | 池田 琉俊 |
| v0.15.0 | 2026/10/11 | CLI のトークンの有効期限を，最後に使ってから30日のスライド式（上限なし）に決定．4.1.2 の `api_tokens` と `web_sessions` に，延長の書き込みを1日に1回までとする規則を追加．4.3.1 に `401` の `token_expired` / `invalid_token` を追加し，4.5.4 に期限の規則と CLI の `401` の扱い（トークンファイルを消して終了コード 1，自動でログインしない）を追加．4.5.8，4.6，6・7章を整合し，9章で CLI トークンの有効期限を期限切れの行の掃除に置き換えた | 池田 琉俊 |
| v0.16.0 | 2026/10/11 | CLI の配布とビルドの方針を決定．4.5.1 で依存を標準ライブラリと cobra に改め，接続先を埋め込みの本番 URL（`CAMPASS_API_URL` で上書き）とし，`User-Agent` を追加．4.5.2 に `version` と `completion` を追加し，4.5.8 CLI の配布（GoReleaser，`cli/vX.Y.Z` のタグ，6つの対象，GitHub Releases・`go install`・Homebrew・deb / rpm，署名しないこと）を新設して，未決事項を 4.5.9 へ移した．5.5 にコマンドの解析の比較（cobra と `flag`）を追加し，7章に CLI のバージョンと接続先のテストを追加．9章で CLI の配布方法を CLI とバックエンドの互換性に置き換えた | 池田 琉俊 |
| v0.17.0 | 2026/10/11 | マップ一覧画面（S-01）を廃止し，マップ一覧を S-02・S-03 に出す開閉できるサイドバーに変更．4.4 の画面と URL から S-01 を削除して `/`・`/maps`・ログイン直後の転送を追加し，サイドバー（中身，広い画面と狭い画面での出し方，開閉，`localStorage` での保持）と一覧と表示の同期（サイドバーが開いている間だけ一覧を30秒ごとに取得，タブが前面に戻ったときにマップを取り直す）を新設．生成の状態，マップの削除（S-03 のメニューからの削除，削除後の移り先，今いる画面のままのお知らせ）を整合し，7章のストリーミングの E2E テストの期待値を直した．4.1.2 で `maps.updated_at` を更新する操作を定め（共有のノードが他のマップから変わっても更新しない），7章にそのテストを追加し，4.3.1 で `GET /api/maps` を `updated_at` の新しい順とした．9章に開いたままの S-03 の同期（#24）を追加し，ADR 0007 を追加 | 池田 琉俊 |
| v0.18.0 | 2026/10/12 | 開いている S-03 の同期を決定（#24）．4.4 の一覧と表示の同期で，S-03 の内容を画面に戻ってきたとき（`visibilitychange` で `visible` になったとき，または `window` の `focus`．2秒以内は取り直さない）だけ取り直すとし，その理由と，取り直した内容の反映の規則（置き換えて視点と拡大率を保つ，詳細パネルの取り直し，外されたノード，編集の途中，削除されたマップ）を追加．サイドバーの一覧を取得するきっかけも同じ判定にそろえた．4.2.10 に同時の編集（後から保存したほうが勝つ）を追加し，7章に開いている S-03 の同期と同時の編集のテストを追加し，9章で開いたままの S-03 の同期を同時の編集の衝突に置き換えた．ADR 0007 に決定を追記 | 池田 琉俊 |
| v0.18.1 | 2026/10/12 | 7章に生成ジョブのテスト（#19）を追加．確かめる振る舞い（ハートビート，行ロック，遅れたジョブ，例外，文言，生成中のマップの削除），時刻の進め方，並行実行の再現方法（一時停止で順番を固定，実際の MySQL，トランザクションでの巻き戻しを切る），LLM のスタブ，Minitest を前提とすることを記載 | 池田 琉俊 |
| v0.19.0 | 2026/10/12 | LLM マップ生成のプロトタイプ（#20，ブランチ `prototype/llm-map-generation`）の結論を反映．4.2.2 で `node_count_target` を検証する範囲とし，サブノード数の目安を追加．4.2.4 に `from` の意味（前提だけ），ゴール（最後のメインノード）へつながらないノードとメインノード数の範囲外の検証エラー，再利用したノードの中身全体の書き直しと保存の規則（あるものは無視し，消さない），構造化出力に特有の点（件数を JSON Schema で強制しない，再生成で前回の出力と検証エラーを渡す）を追加し，4.3.1 の `invalid_map` を整合．4.3.2 に LLM の抽象インタフェース，Faraday による Gemini の直接呼び出し，`LLM_PROVIDER` / `LLM_MODEL` を追加し，5.2 に応答時間の実測を追加．7章で孤立ノードの検出をゴールへつながらないノードの検出にまとめ，検証，再利用，再生成，難易度のテストを追加し，9章に再生成と保存済みのノードを追加 | 池田 琉俊 |
| v0.20.0 | 2026/10/12 | 学習オプトアウトを API のプランで守る形に変更（#25）．4.3.2 で，リクエストに設定を付けることと送信前の検証をやめ，本番のサービスでは学習に使わない契約のプランのキーだけを使うとし，Gemini のどのプランなら学習に使われないか（規約の URL と確かめた日付），デプロイの手順での確認，利用者のキーは #27 で決めることを追加．3.1 の図，6章，7章のセキュリティテストを整合し，9章に利用者の API キーを追加 | 池田 琉俊 |
| v0.21.0 | 2026/10/12 | 自分の LLM API キーの設定（ReqDef F-020，#27）を追加．4.1 に `user_llm_credentials` を追加し，`generation_error_code` に `user_api_key_invalid` と `user_api_key_quota_exceeded` を追加．4.2.9 で生成ジョブが始まったときのキーを使い続けるとし，4.3.1 に会社とモデルの候補・キーの設定の API（`GET /api/llm_providers`，`GET` / `PUT` / `DELETE /api/llm_credential`）と保存のときのエラー，ゴール候補の API のエラーを追加．4.3.2 で LLM の抽象インタフェースに「キーとモデルを確かめる」役割を足し，同時に使うのは1社だけとしていた LLM の選び方を，サービスのキーと利用者のキーに分けて書き直し，キーの使い分け（サービスのキーに切り替えない）と，利用者のキーが学習に使わせない約束の対象外であることを追加．4.4 に S-06 設定を追加し，サイドバーを S-06 にも出して下に設定の入口を置いた．4.5.3 に，利用者のキーで失敗したときにブラウザの設定へ案内することを追加．6章に暗号化，鍵の管理，返さない・ログに出さないことを，7章に利用者の API キーのテストを追加し，9章から利用者の API キーを削除 | 池田 琉俊 |
