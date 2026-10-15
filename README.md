# Campass

## 概要

このプロジェクトは，独学における「次に何を学べばいいかわからない」「今やっている基礎学習が何に繋がっているか見えず飽きてしまう」という課題を解決するためのものです．LLM（生成AI）を活用し，ユーザーの最終ゴールから逆算して必要な知識を積み上げていくプロセスを動的に生成・提示します．

「マップを広げて，コンパスを確かめる」がアプリの考え方（と名前の由来）です．

* **マップ:** 1つのゴールに向かうノード（学習項目）と，その間の道（推奨する学習順序）をネットワーク図として表示します．ゴールごとに独立したマップを複数持てます．
* **コンパス:** そのマップでの現在地（最後に開始または完了したノード）から，今進められるノードをすべて指し示します．どのノードに進むかは学習者が選べます．
* **ノードの共有:** ノードはユーザーの持ち物で，複数のマップで共有されます．あるマップで学んだことは，他のマップでも既知として扱われます．

主な機能は次のとおりです．

| 機能カテゴリ | 機能名 | 概要 |
| :--- | :--- | :--- |
| **初期入力** | ゴール提案と難易度選択 | 曖昧な入力に対して LLM がゴール候補を3つ提案．「ライト」「スタンダード」「ディープ」の3段階から学習の深さを選択． |
| **AI連携** | マップの動的生成 | LLM がマップ（ノード，道，サブノード，寄り道）を生成．できたノードから順に画面に表示．既存のノードと同じ内容は新しく作らず再利用． |
| **マップ表示** | コンパス | 現在地と，今進められるノード（コンパス候補）を指し示す．重要度の高い候補を強調． |
| **マップ表示** | ドリルダウン | 最初はメインノードだけを表示し，ノードを選ぶとその中のサブノードを展開． |
| **マップ表示** | 寄り道 | ゴールとの関係は薄いが興味があれば学べるテーマを提示し，そこから新しいマップを作成． |
| **学習管理** | 複数マップ・ノードの共有 | ゴールごとにマップを作成し，ノードと進捗をマップ間で共有． |
| **学習管理** | ノードの編集 | LLM が作ったマップのノード，道，サブノード，重要度を自分で編集． |
| **クライアント** | CLI | ターミナルから Web と同じようにマップの作成・確認，進捗の更新，編集を行う． |
| **アカウント** | ログイン・自分の API キー | Google / GitHub でログイン．自分の LLM API キーを設定して使うこともできる． |

技術スタックは，React（SPA），Ruby on Rails 7.1（API モード，Ruby 4.0.5），Go（CLI），MySQL 8.0，Gemini（最初の LLM）で，開発環境は Docker Compose で動かします．依存ライブラリを含む詳細は [基本設計書 2.5](docs/basic-design.md) を参照してください．

> **開発状況:** 設計段階です．バックエンド・フロントエンド・CLI はまだ実装されていません．

## インストール

1. リポジトリをクローンします．

   ```bash
   git clone https://github.com/ryuma-1/Campass.git
   cd Campass
   ```

2. リポジトリ直下に `.env` を作成し，次の値を設定します（git には含めません）．`.env` は `backend` コンテナにだけ渡されます．

   | 変数 | 内容 |
   | :--- | :--- |
   | `GEMINI_API_KEY` | Gemini の API キー |
   | `LLM_PROVIDER`，`LLM_MODEL` | 使う LLM（例：`gemini`，`gemini-3.1-flash-lite`） |
   | `MYSQL_ROOT_PASSWORD`，`MYSQL_DATABASE`，`MYSQL_USER`，`MYSQL_PASSWORD` | MySQL の設定 |
   | `GOOGLE_CLIENT_ID`，`GOOGLE_CLIENT_SECRET`，`GITHUB_CLIENT_ID`，`GITHUB_CLIENT_SECRET` | Web ログイン用の OAuth の設定 |
   | `FRONTEND_ORIGIN` | フロントエンドのオリジン（開発環境では `http://localhost:5173`） |
   | `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`，`ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY`，`ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` | 利用者の API キーの暗号化に使う鍵（`bin/rails db:encryption:init` で作成．失うと保存済みのキーを読めなくなる） |

3. コンテナをビルドして起動し，gem をインストールします．

   ```bash
   docker compose up -d --build      # backend と db を起動
   docker compose exec backend bash  # backend コンテナに入る
   bundle install                    # backend コンテナの中で
   ```

   `frontend` と `cli` のサービスは既定では起動しません（`profiles` で分けています）．

## 使い方

1. 今動かせるのは，Gemini API の動作確認と CLI のテストだけです．

   ```bash
   ruby gemini_comu.rb                       # backend コンテナの中で：Gemini API の動作確認
   docker compose run --rm cli go test ./... # CLI のテスト
   ```

2. 実装後は，Web で次のように使います．
   1. Google または GitHub でログインする．
   2. 深く学びたいことを入力し，ゴール候補から1つと難易度を選ぶ．
   3. マップが生成され，できたノードから順に表示される．
   4. コンパスが指すノードを選んで学習を始め，終わったら完了にする．コンパスが次に進めるノードを指し直す．

3. CLI（予定）では，同じ操作をサブコマンドで行い，結果を JSON で出力します．

   ```bash
   campass login                     # ブラウザで許可してトークンを受け取る
   campass goals "機械学習を深く知りたい" # ゴール候補の提案
   campass new                       # マップを作って生成を始める
   campass map <map_id>              # マップとコンパス
   campass start <map_id> <node_id>  # 学習を始める
   campass done <map_id> <node_id>   # 完了にする
   ```

   コマンドの一覧は [基本設計書 4.3](docs/basic-design.md) を参照してください．

## 運用

1. [GitHub Issues](https://github.com/ryuma-1/Campass/issues) に課題を立てる．
2. `main` からブランチを作り（例：`docs/...`，`chore/...`），変更を加える．用語は [GLOSSARY.md](GLOSSARY.md) に従う．
3. プルリクエストを送信し，`main` にマージする．

## ライセンス

ライセンスは未定です．

## 更新履歴

* 2026/10/15: README.md をテンプレートの構成に合わせて書き直し，技術スタックと開発環境の手順を設計書に合わせて更新
