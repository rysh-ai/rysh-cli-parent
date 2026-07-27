# Build workspace for the open-source Rysh CLI.
#
#   rysh-cli-code    the CLI itself   (github.com/rysh-ai/rysh-cli-code)
#   rysh-cli-shared  shared library   (github.com/rysh-ai/rysh-cli-shared)
#
# Both are git submodules. go.work wires them together so a change in the
# shared module is picked up by the CLI without a release round-trip.
#
#   make bootstrap && make build     ->  bin/rysh
#
SHELL := /bin/bash

GO      ?= go
BIN     := bin/rysh
CODE    := rysh-cli-code
SHARED  := rysh-cli-shared

VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
COMMIT  ?= $(shell git -C $(CODE) rev-parse --short HEAD 2>/dev/null || echo none)
DATE    ?= $(shell date -u +%Y-%m-%dT%H:%M:%SZ)

LDFLAGS := -s -w \
	-X main.version=$(VERSION) \
	-X main.commit=$(COMMIT) \
	-X main.date=$(DATE)

# Pin the workspace explicitly: targets cd into the submodules, and a developer
# with GOWORK=off exported for another checkout would otherwise silently build
# against the published rysh-cli-shared instead of the sibling one.
export GOWORK := $(CURDIR)/go.work

PREFIX ?= $(HOME)/.local

.DEFAULT_GOAL := build
.PHONY: help bootstrap build install test vet fmt-check ci clean

help: ## List targets
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

bootstrap: ## Fetch the submodules
	git submodule update --init --recursive

build: bootstrap ## Build the rysh binary into bin/
	@mkdir -p bin
	cd $(CODE) && $(GO) build -trimpath -ldflags '$(LDFLAGS)' -o ../$(BIN) .
	@echo "built $(BIN) ($(VERSION))"

install: build ## Install the binary into ~/.local/bin (override with PREFIX=)
	install -d $(PREFIX)/bin
	install $(BIN) $(PREFIX)/bin/rysh
	@echo "installed $(PREFIX)/bin/rysh — make sure $(PREFIX)/bin is on your PATH"

test: ## Run the test suite of both modules
	cd $(SHARED) && $(GO) test ./...
	cd $(CODE) && $(GO) test ./...

vet: ## Vet both modules
	cd $(SHARED) && $(GO) vet ./...
	cd $(CODE) && $(GO) vet ./...

fmt-check: ## Fail if anything is not gofmt-clean
	@out=$$(gofmt -l $(CODE) $(SHARED)); \
	if [ -n "$$out" ]; then echo "not gofmt-clean:"; echo "$$out"; exit 1; fi

ci: vet test build ## What CI runs

clean: ## Remove build output
	rm -rf bin
