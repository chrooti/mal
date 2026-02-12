.PHONY: all
all: | deps
	mix compile

deps:
	mix local.hex --force
	mix deps.get

lib/steps/*.ex: all

.PHONY: clean
clean:
	mix clean
	rm -fr deps _build .elixir_ls