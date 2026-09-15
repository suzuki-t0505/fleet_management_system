# 開発ガイドライン (Development Guidelines)

## 0. 本書の位置づけ

- **何を書くか**: 本プロジェクト固有の**進め方**。開発フロー、環境構築、ブランチ・コミット運用、品質ゲート、デプロイ手順、ドメイン固有の実装上の注意
- **何を書かないか**: Elixir / Phoenix の書き方は [coding-rules.md](coding-rules.md)、UIの見た目は [DESIGN-notion.md](DESIGN-notion.md)、ファイルの置き場所は [repository-structure.md](repository-structure.md)
- **対象**: 本リポジトリで実装を行う全員（人・AIエージェントを問わない）

---

## 1. 開発フロー

### 1.1 スペック駆動開発

```
① ドキュメント作成    docs/ で「何を作るか」を定義
        ↓
② 作業計画            .steering/{YYYYMMDD}-{task-name}/ で「今回何をするか」を計画
        ↓
③ 実装                tasklist に従って実装し、進捗を随時更新
        ↓
④ 検証                make check + 動作確認
        ↓
⑤ ドキュメント更新    docs/ への影響を判定し、必要なものを更新
```

### 1.2 実装を始める前に必ず読むもの

1. `CLAUDE.md`（開発フローと対話ルール）
2. 関連する永続ドキュメント（[functional-design.md](functional-design.md) の該当機能、[glossary.md](glossary.md)）
3. [coding-rules.md](coding-rules.md) の該当章 — **コードの書き方は必ずこれに従う**
4. UI を伴う実装の場合は [DESIGN-notion.md](DESIGN-notion.md) — **画面の配色・タイポグラフィ・余白・コンポーネント仕様は必ずこれに従う**
5. **Grep で既存の類似実装を検索する** — 既存パターンに合わせることを、新しく考えることより優先する

### 1.3 ステアリングファイル

作業ごとに `.steering/{YYYYMMDD}-{task-name}/` を作成する。

| ファイル | 内容 |
|---------|------|
| `requirements.html` | 今回の要求内容。対象範囲と対象外を明記する |
| `design.html` | 変更するファイルと変更内容。既存パターンとの対応 |
| `tasklist.html` | 実装単位のタスクリスト。進捗を随時更新する |

`tasklist` の**最終タスクは必ず「永続ドキュメントの更新要否確認」**とする（[repository-structure.md](repository-structure.md) 7.1 の表で判定する）。

### 1.4 ドキュメント作成時のルール

**1ファイルずつ作成し、必ず承認を得てから次に進む**。複数ファイルをまとめて作らない。

---

## 2. 環境構築

### 2.1 初回セットアップ

```bash
make setup
```

`assets` の `npm i` と `mix setup`（`deps.get` → `ecto.create` → `ecto.migrate` → `seeds` → アセットビルド）を実行する。

### 2.2 日常の操作

| コマンド | 内容 |
|---------|------|
| `make up` | コンテナ起動（http://localhost:4000） |
| `make log` | web コンテナのログを追う |
| `make stop` / `make down` | 停止 / 削除 |
| `make mix_reset_db` | DB を作り直す（seeds まで実行） |

**すべての開発コマンドは Docker コンテナ上で実行する**。ホストに Elixir を入れて直接実行しない（バージョン差異の事故を防ぐため）。

単一テストファイルの実行:

```bash
docker compose run --rm web mix test test/core_app/operation_reports_test.exs
```

特定の行だけ実行:

```bash
docker compose run --rm web mix test test/core_app/operation_reports_test.exs:42
```

### 2.3 付随ツール

| ツール | URL | 用途 |
|--------|-----|------|
| pgAdmin4 | http://localhost:7777 | DB の内容確認 |
| Swoosh メールボックス | http://localhost:4000/dev/mailbox | 開発環境で送信したメールの確認 |
| LiveDashboard | http://localhost:4000/dev/dashboard | プロセス・クエリの確認 |

### 2.4 環境変数

開発環境では `.env` を使う。**`.env` とサービスアカウントキーは絶対にコミットしない**（[repository-structure.md](repository-structure.md) 10章）。

新しい環境変数を追加したら、[architecture.md](architecture.md) 5章の表に必ず追記する。

---

## 3. ブランチとコミット

### 3.1 ブランチ

| 種別 | 命名 | 例 |
|------|------|-----|
| 機能追加 | `feature/{内容}` | `feature/vehicle-registry` |
| 不具合修正 | `fix/{内容}` | `fix/odometer-validation` |
| リファクタ | `refactor/{内容}` | `refactor/split-incidents-context` |
| ドキュメント | `docs/{内容}` | `docs/add-glossary` |

- `main` から分岐し、`main` へマージする
- **`main` へ直接コミットしない**
- ステアリングディレクトリ名とブランチ名を揃えると追跡しやすい（`20260401-vehicle-registry` ↔ `feature/vehicle-registry`）

### 3.2 コミット

- 1コミット = 1つの意味のある変更。「作業途中」のコミットを残さない
- メッセージは日本語で、**何をしたか**を1行目に書く

```
車両台帳の一覧画面に拠点絞り込みを追加

- Vehicles.list_vehicles/2 に office_id 条件を追加
- SearchComponents に拠点セレクトを追加
```

- マイグレーションとそれを使うコードは**同じコミットに含める**
- 生成物（`priv/static/assets/`）をコミットしない

### 3.3 プルリクエスト

本文に以下を含める。

| 項目 | 内容 |
|------|------|
| 対応するステアリング | `.steering/{ディレクトリ名}` へのリンク |
| 変更内容 | 何をどう変えたか |
| 確認方法 | 動作確認の手順（画面・操作・期待結果） |
| ドキュメント更新 | 更新したもの / 不要と判断した理由 |

---

## 4. 品質ゲート

### 4.1 プッシュ前に必ず実行する

```bash
make check
```

`mix compile --warnings-as-errors` → `mix format` → `mix credo --all` → `mix test` を順に実行する。**1つでも失敗したらプッシュしない**。

> **注意**: 現時点で `credo` が依存に未追加のため `make mix_credo` は失敗する。実装着手前に `mix.exs` へ追加すること（[architecture.md](architecture.md) 8.2）。

### 4.2 CI と `make check` を一致させる

CI（GitHub Actions）のチェック項目と `make check` の内容は**常に同じ**にする。片方だけにチェックを追加しない。

### 4.3 警告を残さない

`--warnings-as-errors` でビルドするため、未使用変数・非推奨API の警告はすべて解消する。`# credo:disable-for-this-file` での回避は、理由をコメントに書ける場合のみ許可する。

---

## 5. テスト

### 5.1 必ず書くテスト

| 対象 | 内容 |
|------|------|
| Context の公開関数 | 正常系・異常系 |
| **スコープ境界** | 他拠点のデータが取得・更新できないこと。`admin` / `manager` / `member` の3ロールで検証する |
| changeset | [functional-design.md](functional-design.md) 6章の V-1〜V-28 に対応させる |
| LiveView の主要フロー | 日報の作成→提出→承認、事故報告→改善報告→承認 |
| 認可 | `/management` 配下の各画面に各ロールでアクセスし、403 / 404 を検証する |
| Oban ワーカー | 同一条件で2回実行しても重複送信されないこと |

### 5.2 スコープ境界のテストを省略しない

本システムの最大のリスクは**他拠点データの露出**である。Context の一覧・取得・更新関数を追加したら、必ず「別拠点のスコープでは取得できない」テストを対で書く。

```elixir
test "他拠点の車両は取得できない" do
  vehicle = vehicle_fixture(office: office_a())
  scope = manager_scope(office: office_b())

  assert_raise Ecto.NoResultsError, fn ->
    Vehicles.get_vehicle!(scope, vehicle.id)
  end
end
```

### 5.3 フィクスチャ

`test/support/fixtures/{context}_fixtures.ex` に置く。テストファイル内に `defp create_*` を書かない。

### 5.4 テストの命名

`test "..."` の説明は**日本語**で、何が起きるべきかを書く。`describe` は関数名（`describe "list_vehicles/2"`）とする。

---

## 6. ドメイン固有の実装ルール

一般的なコーディングルールではなく、**本システムで守るべき固有の約束**。

### 6.1 Context 関数は必ず `scope` を第1引数に取る

```elixir
def list_vehicles(%Scope{} = scope, params)
def get_vehicle!(%Scope{} = scope, id)
def create_vehicle(%Scope{} = scope, attrs)
```

- **LiveView 側で拠点の絞り込みを行わない**。絞り込みはクエリ層の責務
- `scope` を取らない関数を作ってよいのは、全拠点横断が本質の処理（Oban の期限判定ワーカー）だけ。その場合は関数名か `@doc` に「システム権限で実行する」ことを明記する

### 6.2 日時は UTC 保存・JST 表示

- DB・スキーマは `:utc_datetime`
- 表示・入力の変換は `Utils.ConvertDatetime` に集約する
- **`datetime-local` の入力値はJSTとして扱う**。Context で `parse_input/1` を通してからcastし、フォームには `to_input_value/1` で戻す
- **「今日」の判定は JST で行う**（期限の残日数計算、運行日の未来日チェック）。`Date.utc_today()` をそのまま使わない

### 6.3 物理削除をしない

- `Repo.delete` を使ってよいのは、下書き状態の日報と添付ファイルのレコードのみ
- それ以外は `status` / `employment_type` / `active` の変更で表現する
- UI にも「削除」という語を出さない（[glossary.md](glossary.md) 10章）

### 6.4 監査ログを記録する操作

[functional-design.md](functional-design.md) 9.4 の対象操作を実装したら、同じトランザクション内で `AuditLogs.record/3` を呼ぶ。**後から追加する運用にしない**。

### 6.5 走行距離・金額の計算

- `distance_km` は保存時に算出する。画面から受け取った値を信用しない
- 金額は整数（円）で保持する。浮動小数点を使わない
- 燃費などの割り算は**保存せず表示時に算出**する（分母0のガードを必ず入れる）

### 6.6 Oban ジョブは冪等にする

- 再実行しても同じ結果になるよう、DB のユニーク制約で二重実行を防ぐ
- 判定と送信を分ける（1通 = 1ジョブ）。1件の失敗で全体を止めない
- ジョブ内で例外を握りつぶさない。失敗させてリトライに任せる

### 6.7 個人情報の扱い

- ログに免許証番号・パスワード・トークンを出力しない
- 全社共有されたヒヤリハットを他拠点ユーザーに見せる際は、運転者名・報告者名を伏せる（V-27）

### 6.8 マイグレーションは後方互換で行う

列の削除・リネームは「追加 → 両対応 → 削除」の3段階に分け、別々のデプロイで行う（[architecture.md](architecture.md) 6.3）。

### 6.9 一覧は Utils.Pagination を返す

[coding-rules.md](coding-rules.md) 4.3 は `list_*` の戻り値を `%Scrivener.Page{}` としているが、本プロジェクトは Scrivener を採用していない（[architecture.md](architecture.md) 4.2）。代わりに `CoreApp.Utils.Pagination` の構造体を返す。

```elixir
def list_vehicles(%Scope{} = scope, params \\ %{}) do
  Vehicle
  |> scoped(scope)
  |> order_by([v], asc: v.plate_number)
  |> preload(:office)
  |> Pagination.paginate(params, Repo)
end
```

全件を返す関数は `all_*` とし、ページネーションを行わない（選択肢の生成など、件数が限られる用途に限る）。

### 6.10 UI は DESIGN-notion.md のトークンに従う

画面を作るとき、色・文字サイズ・角丸・余白を**その場で決めない**。[DESIGN-notion.md](DESIGN-notion.md) に定義されたデザイントークンを使う。

| 項目 | 参照先 |
|------|-------|
| 配色 | `colors`（`primary` #0075de / `canvas-soft` #f6f5f4 / `ink` / `hairline` ほか） |
| 文字 | `typography`（`heading-1` 〜 `caption` / `eyebrow`） |
| 角丸 | `rounded`（`xs` 4px 〜 `full`） |
| 余白 | `spacing`（`xxs` 4px 〜 `xxl` 32px）。**クラスは Tailwind の numeric スケールを使う**（`xxs`→`p-1` / `xs`→`p-2` / `sm`→`p-3` / `md`→`p-4` / `lg`→`p-6` / `xl`→`p-7` / `xxl`→`p-8`） |
| 部品 | `components`（`button-primary` / `text-input` / `feature-card` / `ex-data-table-cell` ほか） |

実装上の約束:

- トークンは Tailwind のテーマ変数として `assets/css/app.css` に定義し、**HEEx から直接16進数のカラーコードを書かない**（[architecture.md](architecture.md) 4.8）
- `@theme` に**名前付きの `--spacing-*` を追加しない**。Tailwind 組み込みのサイズ名（`max-w-sm` など）と衝突して既存のレイアウトを壊す
- `DESIGN-notion.md` に該当する部品がある場合は、名前と値を合わせる（一覧テーブルは `ex-data-table-cell`、フォームは `text-input`、ダイアログは `ex-modal-card`）
- 定義にない部品が必要になったら、**その場で作らず `DESIGN-notion.md` に追加してから実装する**
- ステータスバッジなど本システム固有の配色は、`accent-*` のパレットから割り当てる（4.8 の対応表）
- `daisyUI` のコンポーネントは使わない。Tailwind のユーティリティで自前実装する（`AGENTS.md`）

---

## 7. レビュー観点

レビュアーは以下を確認する。

### 7.1 必須（1つでも該当すれば差し戻す）

- [ ] Context 関数が `scope` を受け取り、クエリで拠点条件を付けているか
- [ ] 他拠点データを取得できないテストがあるか
- [ ] `live_session` の `on_mount` と pipeline の認可の強さが一致しているか
- [ ] 監査ログ対象の操作でログを記録しているか
- [ ] 物理削除をしていないか
- [ ] Web 層から `Repo` を直接呼んでいないか
- [ ] 秘密情報がコードに含まれていないか

### 7.2 推奨

- [ ] 既存の類似実装と書き方が揃っているか（[coding-rules.md](coding-rules.md) 準拠）
- [ ] UI が [DESIGN-notion.md](DESIGN-notion.md) のトークンに従っているか（生の16進数カラーコードを書いていないか）
- [ ] 一覧クエリに `preload` があり N+1 が起きないか
- [ ] 新しい業務用語が [glossary.md](glossary.md) に登録されているか
- [ ] エラーメッセージが日本語で、何を直せばよいか分かるか
- [ ] モバイル（375px）で崩れないか（日報・事故報告の画面）

---

## 8. デプロイ

### 8.1 手順

```
1. main へマージ
2. CI（compile / format / credo / test）が通ることを確認
3. イメージをビルドし Artifact Registry へ push
4. マイグレーションを Cloud Run ジョブとして実行
5. Cloud Run に新リビジョンをデプロイ
6. 動作確認（ログイン、ダッシュボード、日報の登録）
```

**アプリ起動時の自動マイグレーションは行わない**（複数インスタンス同時起動での競合を避けるため）。

### 8.2 リリース前チェック

- [ ] マイグレーションが後方互換か（6.8）
- [ ] 新しい環境変数を Cloud Run / Secret Manager に設定したか
- [ ] `architecture.md` 5章の環境変数表を更新したか
- [ ] Oban の cron 設定を変更した場合、staging で発火を確認したか

### 8.3 ロールバック

- アプリのみ: Cloud Run のリビジョンを切り戻す
- **マイグレーションを伴う変更は切り戻せない前提**で設計する。切り戻しが必要になる可能性がある変更は、3段階デプロイで分割する

### 8.4 障害時の確認順

1. Cloud Run のリビジョンとエラーログ（Cloud Logging）
2. Cloud SQL の接続数・CPU
3. Oban のジョブ滞留（`oban_jobs` の `available` / `retryable` 件数）
4. 直近のデプロイ内容

---

## 9. よくある落とし穴

| 症状 | 原因 | 対処 |
|------|------|------|
| 他拠点のデータが見えてしまう | Context 関数で `scope` の条件を付け忘れた | クエリ層に条件を追加し、境界テストを追加する |
| LiveView 遷移で認可が効かない | pipeline の plug だけで `on_mount` を設定していない | `live_session` の `on_mount` に同じ強さの認可を指定する（[coding-rules.md](coding-rules.md) 8.3） |
| 期限アラートが飛ばない | Cloud Run がスケールゼロして Oban の cron が発火していない | min-instances = 1 と CPU always allocated を確認する |
| メールが送れない | Cloud Run から SMTP ポートへ接続しようとしている | HTTP API のアダプタ（SendGrid）を使う |
| 日付が1日ずれる | UTC のまま日付判定している | JST に変換してから日付を取り出す（6.2） |
| フォームで入力した時刻が9時間ずれる | `datetime-local` の値（JST）をそのまま UTC として保存している | `Utils.ConvertDatetime.parse_input/1` で変換し、表示は `to_input_value/1` を使う（6.2） |
| 一覧が遅い | インデックス未作成、または N+1 | 複合インデックスと `preload` を確認する |
| `make check` が失敗する | `credo` 未導入 | `mix.exs` に追加する（4.1） |
| レイアウトが極端に狭くなる・文字が縦一列になる | `@theme` に `--spacing-sm` などを定義し、`max-w-sm` 等の組み込みサイズ名を上書きした | 名前付き spacing トークンを削除し、numeric スケールを使う（6.9） |

---

## 10. ドキュメントの更新

### 10.1 更新の判定

実装が以下に該当する場合、対応するドキュメントを**同じPRで**更新する。

| 実装内容 | 更新するドキュメント |
|---------|-------------------|
| 新しいUIコンポーネント・デザイントークンの追加 | [DESIGN-notion.md](DESIGN-notion.md) |
| 画面・テーブル・業務ルールの追加変更 | [functional-design.md](functional-design.md) |
| 依存ライブラリ・環境変数・インフラ構成の変更 | [architecture.md](architecture.md) |
| 新しいディレクトリ・配置ルールの追加 | [repository-structure.md](repository-structure.md) |
| 新しい業務用語の登場 | [glossary.md](glossary.md) |
| 機能の追加削除・スコープ変更 | [product-requirements.md](product-requirements.md) |
| 開発フロー・運用手順の変更 | 本書 |

### 10.2 矛盾したときの優先順位

```
product-requirements.md > functional-design.md > architecture.md
  > repository-structure.md > coding-rules.md
```

上位を正とし、下位を修正する。上位が誤っている場合は、上位を直してから下位に反映する。

---

## 11. 基盤の整備状況

`.steering/20260913-project-setup` で以下を整備済み。

| 対象 | 状態 |
|------|------|
| 品質ゲート（credo 含む） | `make check` が通る |
| 依存（oban / bcrypt / goth / google_api_storage / gcs_signed_url / nimble_csv） | 追加済み |
| 認証・認可（`Accounts.Scope` / 3種の live_session） | 実装済み |
| 拠点（`offices`） | テーブルと最小 Context のみ（管理画面は未実装） |
| Oban | 起動済み。cron の登録はジョブ実装時に行う |
| デザイントークン | `assets/css/app.css` に定義済み |
| `Layouts.app` | 実装済み。ナビゲーションの未実装リンクは無効表示 |
| テンプレート由来の不整合 | [architecture.md](architecture.md) 8.2 のとおり解消済み |

未着手のもの:

| 対象 | 備考 |
|------|------|
| 業務機能（車両台帳・運転者台帳・運行日報・点検整備・事故ヒヤリ） | 次回以降の作業 |
| Oban ジョブ本体（期限アラートの判定・送信） | ジョブ実装時に cron を登録する |
| `Utils.Gcs`（添付ファイル） | 添付ファイル機能と同時に実装する |
| 本番用 `Dockerfile` と CI | デプロイ準備時に別作業とする |
| フォントの self-host（Inter / Noto Sans JP） | 当面はシステムフォントにフォールバック |
