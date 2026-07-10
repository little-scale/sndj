# sndj Makefile — see CLAUDE.md §4.6
# Requires: wla-65816, wla-spc700, wlalink (WLA-DX), python3, node

VERSION := $(shell sed -n 's/^\.DEFINE VERSION "\(.*\)".*/\1/p' src/main.asm)
GITHASH := $(shell git rev-parse --short HEAD 2>/dev/null || echo nogit)
DIRTY   := $(shell git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null || echo +)
STAMP   := $(GITHASH)$(DIRTY)

BUILD   := build
ROM     := $(BUILD)/sndj.sfc
DEVROM  := $(BUILD)/sndj-$(VERSION)-$(STAMP).sfc

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

$(BUILD)/logo.bin $(BUILD)/logo.inc: tools/makelogo.py art/sndj-logo.png | $(BUILD)
	python3 tools/makelogo.py $(BUILD)/logo.bin $(BUILD)/logo.inc

$(BUILD)/help.inc: tools/makehelp.py help.txt tools/commands.csv | $(BUILD)
	python3 tools/makehelp.py help.txt $(BUILD)/help.inc

$(BUILD)/schemes.bin $(BUILD)/kits.bin $(BUILD)/defaults.bin $(BUILD)/tables.inc $(BUILD)/karptab.inc: tools/maketables.py tools/commands.csv $(wildcard samples/factory.sndjfact) $(wildcard samples/kits.bin) | $(BUILD)
	python3 tools/maketables.py $(BUILD)

$(BUILD)/pool.bin: tools/sndj_pool.py tools/sndj_brr.py $(wildcard samples/factory.sndjfact) $(wildcard samples/pool.bin) | $(BUILD)
	python3 tools/sndj_pool.py $@

# SPC700 driver blob
$(BUILD)/driver.o: src/apu/driver.asm | $(BUILD)
	$(WLASPC) -o $@ src/apu/driver.asm

$(BUILD)/driver.spc700.bin: $(BUILD)/driver.o
	@printf '[objects]\n%s\n' "$(BUILD)/driver.o" > $(BUILD)/linkfile-apu
	$(WLALINK) -S $(BUILD)/linkfile-apu $@

$(BUILD)/main.o: $(SRCS) $(BUILD)/buildid.inc $(BUILD)/font.bin $(BUILD)/logo.bin $(BUILD)/logo.inc $(BUILD)/schemes.bin $(BUILD)/kits.bin $(BUILD)/defaults.bin $(BUILD)/tables.inc $(BUILD)/help.inc $(BUILD)/pool.bin $(BUILD)/driver.spc700.bin
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
	  SNDJ_PHRASE_SHOT=$(abspath $(BUILD)/shot-phrase.png) \
	  SNDJ_SONG_SHOT=$(abspath $(BUILD)/shot-song.png) \
	  SNDJ_INSTR_SHOT=$(abspath $(BUILD)/shot-instr.png) \
	  SNDJ_WAVE_SHOT=$(abspath $(BUILD)/shot-wave.png) \
	  SNDJ_LIVE_SHOT=$(abspath $(BUILD)/shot-live.png) \
	  "$(MESEN)" --testrunner $(abspath $(ROM)) $(abspath $$c) || exit 1; \
	done

shot: all
	@python3 tools/mesen_setup.py
	SNDJ_SHOT=$(abspath $(BUILD)/shot.png) "$(MESEN)" --testrunner $(abspath $(ROM)) $(abspath tools/shot.lua)
	@echo "shot: $(BUILD)/shot.png"

# splash comparison masks pixel rows 112-120 (the version+hash band)
shot-diff: shot
	@python3 tools/shotdiff.py $(BUILD)/shot.png tools/goldens/splash.png 112 120
	@for g in phrase song instr wave live; do \
	  if [ -f $(BUILD)/shot-$$g.png ]; then \
	    python3 tools/shotdiff.py $(BUILD)/shot-$$g.png tools/goldens/$$g.png 8 16; \
	  fi; \
	done

# host-side unit tests, no emulator
test:
	python3 tools/makefont.py /tmp/sndj-font-test.bin > /dev/null
	python3 tools/maketables.py /tmp > /dev/null
	python3 tools/sndj_brr.py --selftest
	python3 tools/sndj_rle.py --selftest
	node user-tools/sndj.js --selftest
	python3 tools/test_sf2.py /tmp/sndj-sf2-fixture.json
	node tools/test_sf2.js /tmp/sndj-sf2-fixture.json
	node tools/test_als.js
	node tools/test_spc.js
	node -e "for (const f of ['user-tools/patcher.html','user-tools/savetool.html','user-tools/als2sndj.html','user-tools/spcexport.html']) { const s = require('fs').readFileSync(f, 'utf8'); const m = s.match(/<script>([^]*?)<\/script>/); new Function(m[1]); } console.log('html tools: parse OK')"
	@echo "test: OK"

dist: all
	cp $(ROM) $(BUILD)/sndj-$(VERSION).sfc
	@echo "dist: $(BUILD)/sndj-$(VERSION).sfc"

clean:
	rm -rf $(BUILD)

FORCE:
