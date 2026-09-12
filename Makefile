.PHONY: setup setup_for_docker_user
.DEFAULT_GOAL := setup

setup:
	docker compose run -w /work/assets --rm web npm i
	docker compose run --rm web mix setup

up:
	docker compose up -d

log:
	docker compose logs web -f --no-log-prefix

stop:
	docker compose stop

down:
	docker compose down

mix_compile:
	docker compose run --rm web mix compile --warnings-as-errors --force

mix_format:
	docker compose run --rm web mix format

mix_credo:
	docker compose run --rm web mix credo --all

mix_test:
	docker compose run --rm web mix test

mix_test_cover:
	docker compose run --rm web mix test --cover

mix_clean:
	docker compose run --rm web mix clean

mix_reset_db:
	docker compose run --rm web mix ecto.reset

check: mix_compile mix_format mix_credo mix_test
