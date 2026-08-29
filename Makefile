.PHONY: test

test:
	nvim --headless -u tests/minimal_init.lua -l tests/domain.lua

integration:
	nvim --headless -u tests/minimal_init.lua "+luafile tests/integration.lua"
