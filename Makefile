NVIM ?= nvim
DEPS := nvim-telescope/telescope.nvim nvim-lua/plenary.nvim Foxinio/editable-telescope.nvim
# Directory holding the dependencies; defaults to lazy.nvim's plugin directory.
# EDITABLE_TELESCOPE_PATH overrides editable-telescope alone.
export DEPS_DIR EDITABLE_TELESCOPE_PATH

.PHONY: check test integration smoke deps

check: test integration smoke

test:
	$(NVIM) --headless -u tests/minimal_init.lua -l tests/domain.lua

integration:
	$(NVIM) --headless -u tests/minimal_init.lua "+luafile tests/integration.lua"
	$(NVIM) --headless -u tests/minimal_init.lua -l tests/filters.lua

smoke:
	$(NVIM) --headless -u tests/minimal_init.lua -l tests/smoke.lua

deps:
	@mkdir -p .deps
	@for r in $(DEPS); do d=".deps/$${r#*/}"; [ -d "$$d" ] || git clone -q --depth 1 "https://github.com/$$r" "$$d"; done
