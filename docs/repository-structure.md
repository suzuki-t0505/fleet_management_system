# リポジトリ構造定義書 (Repository Structure)

## 0. 本書の位置づけ

- **何を書くか**: ファイル・ディレクトリをどこに置くか。新しいファイルを作るときの判断基準
- **何を書かないか**: ファイルの中身の書き方は [coding-rules.md](coding-rules.md)、技術選定の理由は [architecture.md](architecture.md)
- **原則**: **迷ったら既存の同種ファイルの隣に置く**。新しいディレクトリを作る前に、既存の分類で表現できないかを確認する

---

## 1. ルート構成

```
fleet_management_system/
├── .claude/                 # Claude Code の設定・スキル・エージェント定義
├── .steering/               # 作業単位のドキュメント（作業ごとに新規作成）
├── assets/                  # フロントエンド資産（CSS / JS / npm）
├── config/                  # 環境別設定
├── docs/                    # 永続ドキュメント
├── lib/                     # アプリケーションコード
│   ├── core_app/            # ドメイン層
│   └── core_app_web/        # Web 層
├── priv/                    # マイグレーション・静的ファイル・翻訳
├── test/                    # テスト
├── .formatter.exs
├── .gitignore
├── AGENTS.md                # Phoenix 1.8 の実装ガイドライン（フレームワーク由来）
├── CLAUDE.md                # プロジェクトメモリ（開発フローと規約）
├── Dockerfile.dev           # 開発用イメージ
├── Dockerfile               # 本番用イメージ（mix release）※未作成
├── Makefile                 # 開発コマンド
├── README.md
├── docker-compose.yml
├── mix.exs
└── mix.lock
```

### 1.1 ルートに置いてよいもの

ビルド・実行・開発フローの起点となる設定ファイルのみ。**スクリプトや一時ファイルをルートに置かない**。

| 種別 | 置き場所 |
|------|---------|
| 運用スクリプト（データ移行など） | `priv/scripts/` |
| Mix タスク | `lib/mix/tasks/` |
| 調査用の一時ファイル | リポジトリに含めない |

---

## 2. `lib/core_app/` — ドメイン層

### 2.1 配置ルール

[coding-rules.md](coding-rules.md) 2.1 に従い、**Context + スキーマの2層**のみ。サービス層・リポジトリ層を作らない。

```
lib/core_app/
├── application.ex
├── repo.ex
├── mailer.ex
├── release.ex                      # マイグレーション実行（リリース用）
│
├── {context}.ex                    # Context（公開API）— 複数形
├── {context}/
│   ├── {entity}.ex                 # スキーマ — 単数形
│   └── {child_entity}.ex           # 子エンティティ（専用 Context は作らない）
│
├── workers/                        # Oban ワーカー（deadline_alert_worker.ex / alert_mail_worker.ex）
└── utils/                          # 横断ユーティリティ（状態を持たない関数モジュール）
```

### 2.2 Context 一覧

| Context | ディレクトリ | 集約 |
|---------|------------|------|
| `accounts.ex` | `accounts/` | `user.ex` / `user_token.ex` / `user_notifier.ex` / `scope.ex` |
| `offices.ex` | `offices/` | `office.ex` |
| `vehicles.ex` | `vehicles/` | `vehicle.ex` |
| `drivers.ex` | `drivers/` | `driver.ex` |
| `operation_reports.ex` | `operation_reports/` | `operation_report.ex` / `refueling.ex` |
| `maintenances.ex` | `maintenances/` | `maintenance.ex` |
| `incidents.ex` | `incidents/` | `incident.ex` |
| `attachments.ex` | `attachments/` | `attachment.ex` |
| `alerts.ex` | `alerts/` | `alert_notification.ex` / `deadline.ex`（期限の値オブジェクト） / `alert_notifier.ex`（メール組み立て） |
| `audit_logs.ex` | `audit_logs/` | `audit_log.ex` |
| `reports.ex` | （なし） | 集計クエリ専用。スキーマを持たない読み取り専用 Context |

`utils/` には横断的な処理を置く。現時点で `convert_datetime.ex`（JSTの「今日」・表示変換）と `pagination.ex`（一覧の共通ページネーション）がある。

### 2.3 新しいファイルをどこに置くかの判断

| 作りたいもの | 置き場所 | 判断基準 |
|------------|---------|---------|
| 新しい業務エンティティ | 既存 Context のディレクトリ、または新規 Context | **既存集約のライフサイクルに従属するなら子エンティティ**（例: 給油記録は日報に従属 → `operation_reports/`）。独立して作成・削除されるなら新規 Context |
| 複数 Context にまたがる処理 | 呼び出し元の Context | 新しい「サービス層」を作らない。どちらが主かを決めて、その Context に置く |
| 日付・金額・文字列の整形 | `utils/format.ex` | 状態を持たず、ドメイン知識を含まないもの |
| 外部サービスの呼び出し | `utils/{service}.ex` | GCS / メール等。インターフェースを1モジュールに閉じ込める |
| 定期実行・非同期処理 | `workers/{名詞}_worker.ex` | 処理本体は Context に書き、ワーカーは**呼び出しとエラー処理だけ**にする |

### 2.4 分割の目安

Context ファイルが **800行**、または **1ファイルに集約が3つ以上**入った時点で分割する。

---

## 3. `lib/core_app_web/` — Web 層

### 3.1 構成

```
lib/core_app_web/
├── endpoint.ex
├── router.ex
├── telemetry.ex
├── gettext.ex
├── user_auth.ex                    # plug と on_mount（認証・認可）
├── plugs/                          # 独自 plug（1 plug = 1ファイル）
├── controllers/                    # HTML/JSON を返す非 LiveView（エラーページ、ファイルDL）
├── components/
│   ├── core_components.ex          # ジェネレータ由来の基本部品（input / button / table ...）
│   ├── layouts.ex
│   ├── layouts/
│   │   ├── root.html.heex
│   │   └── app.html.heex
│   └── {名詞}_components.ex        # 自作の共通コンポーネント
└── live/
    └── {resource}_live/
        ├── index.ex                # 一覧
        ├── show.ex                 # 詳細
        ├── form.ex                 # 新規・編集
        └── {role}/                 # ロールでUIが分かれる場合のみ
```

### 3.2 LiveView のディレクトリ

| リソース | ディレクトリ | ロール別サブディレクトリ |
|---------|------------|----------------------|
| ダッシュボード | `dashboard_live/` | なし（1モジュール内でロール分岐） |
| 運行日報 | `operation_report_live/` | `member/` `manager/` |
| 事故・ヒヤリ | `incident_live/` | `member/` `manager/` |
| 車両 | `vehicle_live/` | `member/`（参照専用）`manager/` |
| 運転者 | `driver_live/` | `manager/`（管理者・運行管理者のみ） |
| 点検整備 | `maintenance_live/` | `manager/`（管理者・運行管理者のみ） |
| 期限アラート | `alert_live/` | `manager/`（管理者・運行管理者のみ） |
| 集計レポート | `report_live/` | なし |
| 拠点 | `office_live/` | なし（管理者のみ） |
| ユーザー | `user_live/` | なし（管理者のみ） |
| 監査ログ | `audit_log_live/` | なし（管理者のみ） |

**ロール別サブディレクトリを作る基準**: 同一リソースで**画面の構成要素そのものが変わる**場合のみ分ける。表示項目の出し分け程度なら1モジュール内で分岐する。

サブディレクトリ名は**ロール値**（`manager` / `member`）に合わせる。`driver` は運転者台帳のレコードを指す語であり、ロールではない（[glossary.md](glossary.md) 1章）。

列挙値の日本語表示は、リソースごとに `{resource}_live/labels.ex` に集約する（例: `vehicle_live/labels.ex`）。HEEx に日本語のラベルを直接書かない。

### 3.3 コンポーネントの置き場所

| 条件 | 置き場所 |
|------|---------|
| 2つ以上の LiveView で使う | `components/{名詞}_components.ex` |
| 1つの LiveView 内でのみ使う | その LiveView モジュール内の `defp` 関数コンポーネント |
| フォーム部品・ボタン等の汎用部品 | `core_components.ex`（ジェネレータの流儀に合わせる） |

実装済みの共通コンポーネント:

| モジュール | 提供するもの |
|-----------|------------|
| `table_components.ex` | `<.data_table>`（PCはテーブル、`lg`未満はカード） |
| `search_components.ex` | `<.search_bar>` / `<.filter_select>` / `<.filter_checkbox>` |
| `pagination_components.ex` | `<.pagination>`（`Utils.Pagination` を受け取る） |
| `status_components.ex` | `<.status_badge>` / `<.deadline_badge>` / `format_date/1` / `format_datetime/1` |
| `card_components.ex` | `<.section_card>` / `<.definition_list>` / `<.empty_state>` / `<.placeholder>` |

これらは `core_app_web.ex` の `html_helpers` で import 済みのため、LiveView から追加の import なしで使える。

---

## 4. `priv/`

```
priv/
├── repo/
│   ├── migrations/                 # {timestamp}_{動詞_対象}.exs
│   └── seeds.exs                   # 開発用の初期データ（拠点・管理者アカウント）
├── scripts/                        # 運用スクリプト（本番データ移行など）
├── static/                         # 公開静的ファイル
│   ├── assets/                     # ビルド成果物（.gitignore 対象）
│   ├── images/
│   ├── favicon.ico
│   └── robots.txt
└── gettext/                        # 翻訳（エラーメッセージの日本語化）
```

### 4.1 マイグレーション

- 命名: `{timestamp}_{動詞_対象}.exs`（例: `20260401093000_create_vehicles.exs` / `20260410120000_add_locked_until_to_users.exs`）
- 1マイグレーション = 1つの意味のある変更。無関係な変更を同一ファイルにまとめない
- 列の削除・リネームは「追加 → 両対応 → 削除」の3段階に分ける（[architecture.md](architecture.md) 6.3）

### 4.2 seeds

`priv/repo/seeds.exs` は**開発環境で動作確認できる最小データ**を投入する。本番データを含めない。

投入内容: 拠点2件、管理者1・運行管理者1・運転者2のユーザー、車両3台、運転者3名、日報数件

---

## 5. `assets/`

```
assets/
├── css/app.css                     # Tailwind のエントリ（@import "tailwindcss" 形式を維持）
├── js/app.js                       # esbuild のエントリ
├── vendor/                         # npm に無い依存（topbar / heroicons）
├── package.json
└── tsconfig.json
```

### 5.1 ルール

- **バンドルは `app.js` / `app.css` の2本のみ**。レイアウトから外部 CDN の `src` / `href` を参照しない
- テンプレート内にインラインの `<script>` を書かない。JS は LiveView の Hook として `app.js` に登録する
- `@apply` を使わない。ユーティリティクラスを HEEx 側に直接書く
- `app.css` の `@source` 指定（`../../lib/core_app_web`）を維持する。ディレクトリを増やした場合は追記する

---

## 6. `test/`

```
test/
├── core_app/                       # Context・スキーマのテスト
│   └── {context}_test.exs
├── core_app_web/
│   ├── live/{resource}_live_test.exs
│   ├── controllers/
│   └── user_auth_test.exs
├── core_app/workers/               # Oban ワーカーのテスト
├── support/
│   ├── conn_case.ex
│   ├── data_case.ex
│   └── fixtures/
│       └── {context}_fixtures.ex
└── test_helper.exs
```

### 6.1 ルール

- テストファイルは**対象モジュールと同じ階層構造**に置く（`lib/core_app/vehicles.ex` → `test/core_app/vehicles_test.exs`）
- フィクスチャは Context ごとに1ファイル。テストファイル内に `defp create_*` を書かない
- 認可のテストは対象 LiveView のテストファイル内に `describe "認可"` として置く

> **現状の不整合**: `test/fleet_managment_system_web/` はスペル誤りかつモジュール名（`CoreAppWeb`）と不一致。`test/core_app_web/` にリネームする（[architecture.md](architecture.md) 8.2）。

---

## 7. `docs/` — 永続ドキュメント

アプリケーション全体の「何を作るか」「どう作るか」を定義する。頻繁には更新しない。

```
docs/
├── product-requirements.md         # プロダクト要求定義書（何を・誰のために作るか）
├── functional-design.md            # 機能設計書（画面・データ・業務ルール）
├── architecture.md                 # 技術仕様書（技術選定・インフラ・実装方針）
├── repository-structure.md         # 本書（ファイルの置き場所）
├── development-guidelines.md       # 開発ガイドライン（本プロジェクト固有の進め方）
├── coding-rules.md                 # コーディングルール（Elixir/Phoenix の書き方）
├── DESIGN-notion.md                # UIデザインルール（デザイントークン・コンポーネント仕様）
├── glossary.md                     # ユビキタス言語定義
└── ideas/                          # 下書き・壁打ち・技術調査メモ（自由形式）
```

`coding-rules.md` と `DESIGN-notion.md` は**実装時に従う規範**である。

| ドキュメント | いつ従うか |
|------------|-----------|
| `coding-rules.md` | **コードを書くとき**（Elixir / Phoenix の書き方） |
| `DESIGN-notion.md` | **UIをデザイン・実装するとき**（配色・タイポグラフィ・角丸・余白・コンポーネント） |

### 7.1 更新のタイミング

| ドキュメント | 更新が必要になる変更 |
|------------|-------------------|
| `product-requirements.md` | 機能の追加・削除、KPI の変更、スコープの変更 |
| `functional-design.md` | 画面の追加、テーブル定義・業務ルールの変更 |
| `architecture.md` | 依存ライブラリの追加、インフラ構成の変更、実装方針の変更 |
| `repository-structure.md` | 新しいディレクトリの追加、配置ルールの変更 |
| `glossary.md` | 新しい業務用語の登場、用語の対訳変更 |
| `DESIGN-notion.md` | デザイントークンの追加・変更、新しい共通UIコンポーネントの定義 |

実装後の更新漏れを防ぐため、`.steering/` の `tasklist` の最終タスクに「永続ドキュメントの更新要否確認」を必ず含める。

---

## 8. `.steering/` — 作業単位のドキュメント

作業ごとに `.steering/[YYYYMMDD]-[タスク名]/` を作成する（例: `.steering/20260401-vehicle-registry/`）。

```
.steering/{YYYYMMDD}-{task-name}/
├── requirements.html               # 今回の要求内容
├── design.html                     # 変更内容の設計
└── tasklist.html                   # タスクリスト（進捗を随時更新）
```

- 命名は `20260401-add-vehicle-registry` 形式（日付 + ケバブケースのタスク名）
- **完了した作業のディレクトリも削除せず、履歴として残す**
- `docs/` との違い: `.steering/` は「今回何をするか」、`docs/` は「何を作るか」

---

## 9. 命名規則の早見表

| 種別 | 命名 | 例 |
|------|------|-----|
| Context | `snake_case.ex`（複数形） | `operation_reports.ex` |
| Ecto スキーマ | `snake_case.ex`（単数形） | `operation_reports/operation_report.ex` |
| LiveView 一覧 | `index.ex` | `vehicle_live/index.ex` |
| LiveView 詳細 | `show.ex` | `vehicle_live/show.ex` |
| LiveView フォーム | `form.ex` | `vehicle_live/form.ex` |
| コンポーネント | `{名詞}_components.ex` | `pagination_components.ex` |
| Oban ワーカー | `{名詞}_worker.ex` | `deadline_alert_worker.ex` |
| Plug | `{名詞}.ex` | `plugs/no_store_cache.ex` |
| Utils | `{動詞または名詞}.ex` | `utils/convert_datetime.ex` |
| マイグレーション | `{timestamp}_{動詞_対象}.exs` | `20260401093000_create_vehicles.exs` |
| Context テスト | `{context}_test.exs` | `operation_reports_test.exs` |
| フィクスチャ | `{context}_fixtures.ex` | `operation_reports_fixtures.ex` |
| ステアリング | `{YYYYMMDD}-{task-name}/` | `20260401-add-vehicle-registry/` |

DB のテーブル名は**複数形のスネークケース**、カラム名は単数形のスネークケース。真偽値は `active` / `police_reported` のように形容詞・過去分詞で表す。

---

## 10. Git 管理の対象外

`.gitignore` で除外する（既存の設定に加えて維持するもの）:

| パターン | 理由 |
|---------|------|
| `/_build/` `/deps/` `/cover/` | ビルド成果物・依存 |
| `/priv/static/assets/` | アセットのビルド成果物 |
| `/priv/static/cache_manifest.json` | digest の成果物 |
| `/assets/node_modules/` | npm 依存 |
| `.env` / `*.json`（サービスアカウントキー） | **秘密情報**。GCP のキーを絶対にコミットしない |
| `erl_crash.dump` | クラッシュダンプ |

> **要修正**: `.gitignore` の `fleet_managment_system-*.tar` はスペル誤り。アプリ名は `core_app` のため `core_app-*.tar` に修正する。また、サービスアカウントキーの除外パターンが未設定のため追加する。

---

## 11. 参照関係

```
product-requirements.md  （何を・誰のために）
        │
        ▼
functional-design.md     （画面・データ・業務ルール）
        │
        ▼
architecture.md          （技術選定・インフラ・実装方針）
        │
        ▼
repository-structure.md  （ファイルの置き場所）  ← 本書
        │
        ├──────────────┐
        ▼              ▼
coding-rules.md   DESIGN-notion.md
（コードの書き方）  （UIデザインの決まり）
```

下位のドキュメントは上位のドキュメントを前提とする。矛盾が生じた場合は**上位のドキュメントを正とし、下位を修正する**。

`coding-rules.md` と `DESIGN-notion.md` は並列の関係にあり、扱う対象が異なる（コードの書き方 / UIの見え方）。両者が競合することはないが、UIコンポーネントの**実装の書き方**は `coding-rules.md`、**見た目の値**は `DESIGN-notion.md` に従う。
