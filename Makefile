.PHONY: test integration smoke

test:
	nvim --headless -u tests/minimal_init.lua -l tests/domain.lua

integration:
	nvim --headless -u tests/minimal_init.lua "+luafile tests/integration.lua"
	nvim --headless -u tests/minimal_init.lua -l tests/filters.lua

smoke:
	nvim --headless -u tests/minimal_init.lua -l tests/smoke.lua
