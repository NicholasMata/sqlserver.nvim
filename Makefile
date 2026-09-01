NVIM ?= nvim
COMPOSE := docker compose -f tests/integration/compose.yaml
TEST_ROOT := $(CURDIR)/.tests
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

.PHONY: test test-unit test-integration test-integration-local test-all
.PHONY: test-env-up test-env-seed test-env-reset test-env-down

test: test-unit

test-unit:
	$(TEST_ENV) SQLSERVER_TEST_SUITE=unit \
		$(NVIM) --headless --clean -u runtests.lua

test-integration:
	$(TEST_ENV) SQLSERVER_TEST_SUITE=integration \
		$(NVIM) --headless --clean -u runtests.lua

test-integration-local: test-env-seed test-integration

test-all: test-unit test-integration-local

test-env-up:
	$(COMPOSE) up --detach --wait --wait-timeout 180

test-env-seed: test-env-up
	$(COMPOSE) exec --no-TTY sqlserver \
		/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa \
		-P "$(DbPassword)" -C -b -i /fixtures/seed.sql

test-env-reset: test-env-seed

test-env-down:
	$(COMPOSE) down --volumes --remove-orphans
