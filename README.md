# CoreApp

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

## 環境変数

### 本番（`MIX_ENV=prod` / Cloud Run）

`config/runtime.exs` で読み込まれる。必須のものが未設定の場合は起動時に例外で停止する。

| 変数名 | 必須 | 既定値 | 説明 |
| --- | --- | --- | --- |
| `SECRET_KEY_BASE` | ✅ | なし | Cookie・トークンの署名鍵。`mix phx.gen.secret` で生成する |
| `DATABASE_URL` | ✅ | なし | DB接続URL。例: `ecto://USER:PASS@HOST/DATABASE` |
| `GCS_BUCKET` | ✅ | なし | 添付ファイルの保存先 Cloud Storage バケット名 |
| `PHX_SERVER` | ✅ | なし | `true` でHTTPサーバを起動。リリースの `bin/server` が自動設定する |
| `PHX_HOST` | - | `example.com` | 公開ホスト名。URL生成に使う（https / 443固定） |
| `PORT` | - | `4000` | HTTP待ち受けポート。Cloud Run では自動で設定される |
| `POOL_SIZE` | - | `10` | Ecto のDBコネクションプールサイズ |
| `ECTO_IPV6` | - | なし | `true` または `1` でDB接続にIPv6を使う |
| `DNS_CLUSTER_QUERY` | - | なし | クラスタリング用のDNSクエリ。単一インスタンスなら不要 |
| `GOOGLE_APPLICATION_CREDENTIALS` | - | なし | goth が使うサービスアカウント鍵のパス。Cloud Run 上ではメタデータサーバから取得するため不要 |

### 開発（Docker Compose）

`docker-compose.yml` で既定値が入るため、通常は設定不要。

| 変数名 | 必須 | 既定値 | 説明 |
| --- | --- | --- | --- |
| `PGHOST` | - | `db` | PostgreSQL のホスト名 |
| `PGPASSWORD` | - | `postgres` | PostgreSQL のパスワード（`db` コンテナの `POSTGRES_PASSWORD` にも使われる） |

開発環境では添付ファイルはローカルディスク（`priv/uploads`）に保存するため、GCS関連の変数は不要。

### テスト

| 変数名 | 必須 | 既定値 | 説明 |
| --- | --- | --- | --- |
| `PGHOST` | - | `db` | PostgreSQL のホスト名 |
| `MIX_TEST_PARTITION` | - | なし | テストDB名のサフィックス。`mix test --partitions` 使用時のみ |

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix

## Docker push

```bash
docker build -t fleet-management-system --no-cache .
docker tag fleet-management-system asia-northeast1-docker.pkg.dev/dulcet-radar-464207-v2/fleet-management-system/fleet-management-system:v1
docker push asia-northeast1-docker.pkg.dev/dulcet-radar-464207-v2/fleet-management-system/fleet-management-system:v1
```

## Memo

```bash
docker compose exec db pg_dump --data-only --column-inserts -U postgres  -d core_app_dev > test.sql
```

## メモ（ToDo）
現状の変更をブランチを作成してコミット&プッシュ
GCSを利用できるように設定
メールを送信できるようにお名前メールの設定

デプロイ