# snesdj Makefile — see CLAUDE.md §4.6
# Requires: wla-65816, wla-spc700, wlalink (WLA-DX), python3, node

VERSION := $(shell sed -n 's/^\.DEFINE VERSION "\(.*\)".*/\1/p' src/main.asm)
GITHASH := $(shell git rev-parse --short HEAD 2>/dev/null || echo nogit)
DIRTY   := $(shell git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null || echo +)
STAMP   := $(GITHASH)$(DIRTY)

BUILD   := build
ROM     := $(BUILD)/snesdj.sfc
DEVROM  := $(BUILD)/snesdj-$(VERSION)-$(STAMP).sfc

WLA65816 := wla-65816
WLASPC   := wla-spc700
WLALINK  := wlalink
MESEN    ?= $(HOME)/.local/opt/Mesen.app/Contents/MacOS/Mesen

SRCS := $(wildcard src/*.asm src/*.inc src/apu/*.asm)

.PHONY: all run check test shot clean dist FORCE

all: $(ROM)
	@cp $(ROM) $(DEVROM)
	@echo "built $(ROM) ($(VERSION) $(STAMP)) + $(notdir $(DEVROM))"

# build stamp: regenerate every run, but only touch the file when it changes
# (avoids rebuilding the world on every make)
$(BUILD)/buildid.inc: FORCE | $(BUILD)
	@printf '.DEFINE BUILD_STAMP "%s"\n' "$(STAMP)" > $@.tmp
	@cmp -s $@.tmp $@ || cp $@.tmp $@
	@rm -f $@.tmp

$(BUILD):
	@mkdir -p $(BUILD)

$(BUILD)/font.bin: tools/makefont.py | $(BUILD)
	python3 tools/makefont.py $@

$(BUILD)/pal.bin $(BUILD)/gradient.bin $(BUILD)/tables.inc: tools/maketables.py | $(BUILD)
	python3 tools/maketables.py $(BUILD)

$(BUILD)/sample0.brr: tools/sndj_brr.py | $(BUILD)
	python3 tools/sndj_brr.py --gen pad $@

# SPC700 driver blob
$(BUILD)/driver.o: src/apu/driver.asm | $(BUILD)
	$(WLASPC) -o $@ src/apu/driver.asm

$(BUILD)/driver.spc700.bin: $(BUILD)/driver.o
	@printf '[objects]\n%s\n' "$(BUILD)/driver.o" > $(BUILD)/linkfile-apu
	$(WLALINK) -S $(BUILD)/linkfile-apu $@

$(BUILD)/main.o: $(SRCS) $(BUILD)/buildid.inc $(BUILD)/font.bin $(BUILD)/pal.bin $(BUILD)/gradient.bin $(BUILD)/tables.inc $(BUILD)/sample0.brr $(BUILD)/driver.spc700.bin
	$(WLA65816) -I src -I $(BUILD) -o $@ src/main.asm

$(BUILD)/linkfile: | $(BUILD)
	@printf '[objects]\n%s\n' "$(BUILD)/main.o" > $@

$(ROM): $(BUILD)/main.o $(BUILD)/linkfile
	$(WLALINK) -S $(BUILD)/linkfile $(ROM)
	python3 tools/fixsum.py $(ROM)

run: all
	open -a "$(HOME)/.local/opt/Mesen.app" $(ROM)

# emulator-in-the-loop assertions (agent ground truth)
CHECKS := $(wildcard tools/checks/*.lua)
check: all
	@python3 tools/mesen_setup.py
	@for c in $(CHECKS); do \
	  echo "== $$c"; \
	  SNESDJ_PHRASE_SHOT=$(abspath $(BUILD)/shot-phrase.png) \
	  SNESDJ_SONG_SHOT=$(abspath $(BUILD)/shot-song.png) \
	  "$(MESEN)" --testrunner $(abspath $(ROM)) $(abspath $$c) || exit 1; \
	done

shot: all
	@python3 tools/mesen_setup.py
	SNESDJ_SHOT=$(abspath $(BUILD)/shot.png) "$(MESEN)" --testrunner $(abspath $(ROM)) $(abspath tools/shot.lua)
	@echo "shot: $(BUILD)/shot.png"

# splash comparison masks pixel rows 88-96 (the git-stamp text line)
shot-diff: shot
	@python3 tools/shotdiff.py $(BUILD)/shot.png tools/goldens/splash.png 88 96
	@for g in phrase song; do \
	  if [ -f $(BUILD)/shot-$$g.png ]; then \
	    python3 tools/shotdiff.py $(BUILD)/shot-$$g.png tools/goldens/$$g.png; \
	  fi; \
	done

# host-side unit tests, no emulator
test:
	python3 tools/makefont.py /tmp/snesdj-font-test.bin > /dev/null
	python3 tools/maketables.py /tmp > /dev/null
	python3 tools/sndj_brr.py --selftest
	@echo "test: OK"

dist: all
	cp $(ROM) $(BUILD)/snesdj-$(VERSION).sfc
	@echo "dist: $(BUILD)/snesdj-$(VERSION).sfc"

clean:
	rm -rf $(BUILD)

FORCE:
