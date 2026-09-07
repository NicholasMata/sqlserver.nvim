NVIM ?= nvim
STYLUA ?= stylua
LUA_SOURCES := lua ftplugin tests scripts
COMPOSE := docker compose -f tests/integration/compose.yaml
TEST_ROOT := $(CURDIR)/.tests
MINI_NVIM_DIR := $(TEST_ROOT)/deps/mini.nvim
MINI_NVIM_COMMIT := 1345d191bb3da9c7b0e977f4387c5761f9bff68d
TEST_ENV := XDG_CONFIG_HOME=$(TEST_ROOT)/config \
	XDG_DATA_HOME=$(TEST_ROOT)/data \
	XDG_STATE_HOME=$(TEST_ROOT)/state \
	XDG_CACHE_HOME=$(TEST_ROOT)/cache

export DbServer ?= localhost
export DbDatabase ?= master
export DbUser ?= sa
export DbPassword ?= Test_Password_123
export SQLSERVER_PORT ?= 1433

.NOTPARALLEL: test-all test-integration-local

.PHONY: format format-check lint lint-doc-filenames
.PHONY: test test-deps test-unit test-integration test-integration-local test-all assert-no-process-leaks
.PHONY: test-env-up test-env-seed test-env-reset test-env-down

test: test-unit

format:
	$(STYLUA) $(LUA_SOURCES)

format-check:
	$(STYLUA) --check $(LUA_SOURCES)

lint: format-check lint-doc-filenames

lint-doc-filenames:
	@invalid=$$(find docs -type f | awk -F/ '$$NF !~ /^[a-z0-9]+(-[a-z0-9]+)*\.[a-z0-9]+$$/'); \
		test -z "$$invalid" || { printf 'Documentation filenames must use lowercase kebab-case:\n%s\n' "$$invalid" >&2; exit 1; }

test-deps:
	@test -f "$(MINI_NVIM_DIR)/lua/mini/test.lua" || { \
		mkdir -p "$(TEST_ROOT)/deps"; \
		git clone --filter=blob:none https://github.com/nvim-mini/mini.nvim.git "$(MINI_NVIM_DIR)"; \
	}
	@git -C "$(MINI_NVIM_DIR)" checkout --quiet "$(MINI_NVIM_COMMIT)"

test-unit: test-deps
	$(TEST_ENV) SQLSERVER_TEST_SUITE=unit \
		$(NVIM) --headless --clean -u tests/minimal-init.lua -c "lua MiniTest.run()"

test-integration: test-deps
	$(TEST_ENV) SQLSERVER_TEST_SUITE=integration \
		$(NVIM) --headless --clean -u tests/minimal-init.lua -c "lua MiniTest.run()"
	$(MAKE) assert-no-process-leaks

test-integration-local: test-env-seed test-integration

test-all: test-unit test-integration-local

assert-no-process-leaks:
	@tests/assert-no-process-leaks.sh "$(CURDIR)"

test-env-up:
	$(COMPOSE) up --detach --wait --wait-timeout 180

test-env-seed: test-env-up
	$(COMPOSE) exec --no-TTY sqlserver \
		/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa \
		-P "$(DbPassword)" -C -b -i /fixtures/seed.sql

test-env-reset: test-env-seed

test-env-down:
	$(COMPOSE) down --volumes --remove-orphans
