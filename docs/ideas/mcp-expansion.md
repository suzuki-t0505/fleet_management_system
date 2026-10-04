# MCP機能の拡張アイディア

第1弾（配車表の取り込み）の次に MCP 化する候補。第1弾の仕様は [architecture.md](../architecture.md) 4.9 と [functional-design.md](../functional-design.md) 6.8、ステアリングは `.steering/20261004-mcp-dispatch-import/`。

## 共通の前提（第1弾で作った土台）

- ツールは `lib/core_app_web/mcp/tools/*.ex` に `tools/0` を持つモジュールとして追加し、`CoreAppWeb.Mcp.Tools` の `@modules` に登録する
- 実行は APIトークンの持ち主の `Scope`。Context の公開 API だけを呼ぶ（Repo を直接呼ばない）。MCP は運行管理者以上のみ
- 書き込みは「検証（保存しない）→ 利用者が確認 → 登録」の2段階にする。エラーが1行でもあれば何も登録しない（取り込み系）
- 一覧は件数上限（`Pagination` の上限100、取り込みは200行）を守る
- 新しいツールを足したら `mcp_controller_test.exs` の `tools/list` の期待値を更新する

## 候補（優先度順）

### 1. 期限アラートの照会（読み取り）
- 内容: 車検・保険・定期点検・免許などの期限が近い車両/ドライバーを返す。「今月切れるものは？」に答える
- 既存: `Alerts.list_deadlines/2`・`count_deadlines_by_urgency/1`（期限アラートの Context）
- ツール案: `list_alerts`（`days`、`type`、`office_id`）
- 注意: 読み取りのみで安全。最初に着手しやすい

### 2. 空き車両・ドライバーの検索（読み取り）
- 内容: 指定した日時の範囲に配車が無い車両・ドライバーを返す。「明日 10〜15時に空いている4tは？」
- 既存: `Dispatches.list_dispatches_for_day/3`、`Dispatches.warnings/2` の重なり判定（終了=開始は重ならない）、`Vehicles.all_selectable_vehicles/1`、`Drivers.all_selectable_drivers/1`
- ツール案: `find_available`（`started_at`、`ended_at`、`kind: vehicle|driver`、`vehicle_class`）
- 注意: 判定は `[started_at, ended_at)` の半開区間で統一する。整備中（`maintenance`）の車両は除外する

### 3. 売上集計（読み取り）
- 内容: 月 × 荷主/車両/ドライバー/拠点の配車売上
- 既存: `Reports.dispatch_revenue_report/2`、`Reports.all_report_rows/3`（運行距離・燃費・整備費・事故の集計も同じ形）
- ツール案: `get_report`（`report`、`from`、`to`、`axis`）
- 注意: 売上は承認の概念が無く全配車が対象（[functional-design.md](../functional-design.md) 8章）。走行距離などは承認済み日報のみ

### 4. 配車の更新・取消し（書き込み）
- 内容: 表の修正を反映する（時間変更・ドライバー変更・料金修正）
- 既存: `Dispatches.update_dispatch/4`（`ensure_same_office` で他拠点は拒否）
- ツール案: `update_dispatch`（`id` ＋ 変更項目）、`validate_dispatch_update`
- 注意: 取消し（削除）は現状 Context に無い。必要なら「無効化」か削除かを先に決める。取り込みと同じく差分を見せてから実行する。更新の既存検証（V-30〜V-37）を再利用する

### 5. 荷主の登録（書き込み）
- 内容: 取り込みで「未登録」エラーになった荷主を、確認後に登録する
- 既存: `Shippers.create_shipper/3`（名前の重複は `unique_constraint`）
- ツール案: `create_shipper`（`name`、`code`、`note`）
- 注意: 第1弾の決定は「自動作成しない」。**利用者が名称を確認してから呼ぶ**前提のツールにする。車両・ドライバーは台帳（免許・車検など必須項目が多い）なので MCP では作らない

### 6. 整備記録の一括取り込み（書き込み）
- 内容: 整備の Excel を点検整備記録として取り込む（配車と同じ流れ）
- 既存: `Maintenances.create_maintenance/3`、`change_maintenance/3`、`warnings/2`
- 実装案: `Dispatches.Import` と同じ構成（名称→車両の解決、検証、全行有効のときだけ登録、二重登録検知）。共通部分（`normalize_name/1`、エラー整形）は取り出して共用する
- 注意: 二重登録の判定キーを決める（車両＋実施日＋区分など）

### 7. 参照系の追加（読み取り）
- 運行日報（`OperationReports.list_operation_reports/2`）、事故・ヒヤリ（`Incidents`）、CSV出力（`Exports`）の要約
- 注意: 事故・ヒヤリは機微な情報を含む。拠点スコープと全社共有フラグの扱いを先に確認する

## 横断の改善（必要になったら）

- トークンに名前（用途）と最終利用日時を付ける（`users_tokens` に列追加）。複数発行したときの区別と棚卸しのため
- 管理者がユーザーのトークンを一覧・失効できる画面（退職・紛失時）
- MCP の操作ログ（どのツールをいつ呼んだか）。現状は登録系が監査ログに残るだけ
- レート制限。トークン漏えい時の被害を抑える
- 取り込みの列マッピング例（配車表のサンプル）を README に追加
