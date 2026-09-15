# CoreApp

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

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