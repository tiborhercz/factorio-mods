MOD_NAME := improved-item-names

VERSION := $(shell grep -E '"version"' info.json | head -1 | sed -E 's/.*: *"([^"]+)".*/\1/')
ZIP := $(MOD_NAME)_$(VERSION).zip

MOD_DIR := $(CURDIR)

UNAME := $(shell uname -s)
ifeq ($(UNAME),Darwin)
	MODS_DIR ?= $(HOME)/Library/Application Support/factorio/mods
else
	MODS_DIR ?= $(HOME)/.factorio/mods
endif

LINK := $(MODS_DIR)/$(MOD_NAME)

.PHONY: install
install:
	@test -d "$(MODS_DIR)" || { echo "Mods dir not found: $(MODS_DIR)"; echo "Set it explicitly: make install MODS_DIR=/path/to/mods"; exit 1; }
	@ln -sfn "$(MOD_DIR)" "$(LINK)"
	@echo "Linked: $(LINK) -> $(MOD_DIR)"

# Package a portal-ready zip: a single top-level folder named after the mod,
# containing only the files Factorio needs (no Makefile, no .git).
.PHONY: zip
zip:
	@rm -rf build "$(ZIP)"
	@mkdir -p "build/$(MOD_NAME)"
	@cp -r info.json locale "build/$(MOD_NAME)/"
	@[ -f changelog.txt ] && cp changelog.txt "build/$(MOD_NAME)/" || true
	@[ -f thumbnail.png ] && cp thumbnail.png "build/$(MOD_NAME)/" || true
	@[ -f LICENSE ] && cp LICENSE "build/$(MOD_NAME)/" || true
	@cd build && zip -r -q "../$(ZIP)" "$(MOD_NAME)"
	@rm -rf build
	@echo "Built $(ZIP)"

.PHONY: clean
clean:
	@rm -rf build $(MOD_NAME)_*.zip
	@echo "Cleaned build artifacts"
