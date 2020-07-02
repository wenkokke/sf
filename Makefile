SHELL := /usr/bin/env bash
AGDA := $(shell find . -type f -and \( -path '*/src/*' -or -path '*/courses/*' \) -and -name '*.lagda.md')
AGDAI := $(shell find . -type f -and \( -path '*/src/*' -or -path '*/courses/*' \) -and -name '*.agdai')
LUA := $(shell find . -type f -and -path '*/epub/*' -and -name '*.lua')
MARKDOWN := $(subst courses/,out/,$(subst src/,out/,$(subst .lagda.md,.md,$(AGDA))))
PLFA_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
LUA_VERSION := $(lua -e "print(string.sub(_VERSION,5))")
LUA_MODULES := lua_modules/

ifneq ($(wildcard $(LUA_MODULES)),)
	LUA_FLAGS += -l epub/set_paths
endif

ifeq ($(AGDA_STDLIB_VERSION),)
AGDA_STDLIB_URL := https://agda.github.io/agda-stdlib/
else
AGDA_STDLIB_URL := https://agda.github.io/agda-stdlib/v$(AGDA_STDLIB_VERSION)/
endif


# Build PLFA and test hyperlinks
test: build
	ruby -S bundle exec htmlproofer '_site'


# Build PLFA and test hyperlinks offline
test-offline: build
	ruby -S bundle exec htmlproofer '_site' --disable-external


# Build PLFA and test hyperlinks for stable
test-stable-offline: $(MARKDOWN)
	ruby -S bundle exec jekyll clean
	ruby -S bundle exec jekyll build --destination '_site/stable' --baseurl '/stable'
	ruby -S bundle exec htmlproofer '_site' --disable-external


out/:
	mkdir -p out/

# EPUB generation notes
#
# - The "Apple Books" app on Mac does not show syntax highlighting.
#   The Thorium app on Mac, however, does.
#
# - Regarding --epub-chapter-level, from the docs (https://pandoc.org/MANUAL.html):
#
#       "Specify the heading level at which to split the EPUB into separate “chapter”
#       files. The default is to split into chapters at level-1 headings. This option
#       only affects the internal composition of the EPUB, not the way chapters and
#       sections are displayed to users. Some readers may be slow if the chapter
#       files are too large, so for large documents with few level-1 headings, one
#       might want to use a chapter level of 2 or 3."

epub: out/epub/plfa.epub

out/epub/:
	mkdir -p out/epub/

out/epub/plfa.epub: out/epub/ | $(AGDA) $(LUA) epub/main.css out/epub/acknowledgements.md
	pandoc --strip-comments \
		--css=epub/main.css \
		--epub-embed-font='assets/fonts/mononoki.woff' \
		--epub-embed-font='assets/fonts/FreeMono.woff' \
		--epub-embed-font='assets/fonts/DejaVuSansMono.woff' \
		--lua-filter epub/include-files.lua \
		--lua-filter epub/rewrite-links.lua \
		--lua-filter epub/rewrite-html-ul.lua \
		--lua-filter epub/default-code-class.lua -M default-code-class=agda \
		--standalone \
		--fail-if-warnings \
		--toc --toc-depth=2 \
		--epub-chapter-level=2 \
		-o "$@" \
		epub/index.md

out/epub/acknowledgements.md: src/plfa/acknowledgements.md _config.yml
	lua $(LUA_FLAGS) epub/render-liquid-template.lua _config.yml $< $@


# Convert literal Agda to Markdown
define AGDA_template
in := $(1)
out := $(subst courses/,out/,$(subst src/,out/,$(subst .lagda.md,.md,$(1))))
$$(out) : in  = $(1)
$$(out) : out = $(subst courses/,out/,$(subst src/,out/,$(subst .lagda.md,.md,$(1))))
$$(out) : $$(in) | out/
	@echo "Processing $$(subst ./,,$$(in))"
ifeq (,$$(findstring courses/,$$(in)))
	./highlight.sh $$(subst ./,,$$(in)) --include-path=src/
else
# Fix links to the file itself (out/<filename> to out/<filepath>)
	./highlight.sh $$(subst ./,,$$(in)) --include-path=src/ --include-path=$$(subst ./,,$$(dir $$(in)))
endif
endef

$(foreach agda,$(AGDA),$(eval $(call AGDA_template,$(agda))))


# Start server
serve:
	ruby -S bundle exec jekyll serve --incremental


# Start background server
server-start:
	ruby -S bundle exec jekyll serve --no-watch --detach


# Stop background server
server-stop:
	pkill -f jekyll


# Build website using jekyll
build: $(MARKDOWN)
	ruby -S bundle exec jekyll build


# Build website using jekyll incrementally
build-incremental: $(MARKDOWN)
	ruby -S bundle exec jekyll build --incremental


# Remove all auxiliary files
clean:
	rm -f .agda-stdlib.sed .links-*.sed out/epub/acknowledgements.md
ifneq ($(strip $(AGDAI)),)
	rm $(AGDAI)
endif


# Remove all generated files
clobber: clean
	ruby -S bundle exec jekyll clean
	rm -rf out/

.phony: clobber


# List all .lagda files
ls:
	@echo $(AGDA)

.phony: ls


# MacOS Setup (install Bundler)
macos-setup:
	brew install libxml2
	ruby -S gem install bundler --no-ri --no-rdoc
	ruby -S gem install pkg-config --no-ri --no-rdoc -v "~> 1.1"
	ruby -S bundle config build.nokogiri --use-system-libraries
	ruby -S bundle install

.phony: macos-setup


# Travis Setup (install Agda, the Agda standard library, acknowledgements, etc.)
travis-setup:\
	$(HOME)/.local/bin/agda\
	$(HOME)/.local/bin/acknowledgements\
	$(HOME)/agda-stdlib-$(AGDA_STDLIB_VERSION)/src\
	$(HOME)/.agda/defaults\
	$(HOME)/.agda/libraries\
	lua_modules/share/lua/$(LUA_VERSION)/cjson\
	lua_modules/share/lua/$(LUA_VERSION)/tinyyaml.lua\
	lua_modules/share/lua/$(LUA_VERSION)/liquid.lua\
	/usr/bin/pandoc

.phony: travis-setup


travis-install-acknowledgements: $(HOME)/.local/bin/acknowledgements

$(HOME)/.local/bin/acknowledgements:
	curl -L https://github.com/plfa/acknowledgements/archive/master.zip -o $(HOME)/acknowledgements-master.zip
	unzip -qq $(HOME)/acknowledgements-master.zip -d $(HOME)
	cd $(HOME)/acknowledgements-master;\
		stack install

# The version of pandoc on Xenial is too old.
/usr/bin/pandoc:
	curl -L https://github.com/jgm/pandoc/releases/download/2.9.2.1/pandoc-2.9.2.1-1-amd64.deb\
	     -o $(HOME)/pandoc.deb
	sudo dpkg -i $(HOME)/pandoc.deb

travis-uninstall-acknowledgements:
	rm -rf $(HOME)/acknowledgements-master/
	rm $(HOME)/.local/bin/acknowledgements

travis-reinstall-acknowledgements: travis-uninstall-acknowledgements travis-reinstall-acknowledgements

.phony: travis-install-acknowledgements travis-uninstall-acknowledgements travis-reinstall-acknowledgements


travis-install-agda:\
	$(HOME)/.local/bin/agda\
	$(HOME)/.agda/defaults\
	$(HOME)/.agda/libraries

$(HOME)/.agda/defaults:
	echo "standard-library" >> $(HOME)/.agda/defaults
	echo "plfa" >> $(HOME)/.agda/defaults

$(HOME)/.agda/libraries:
	echo "$(HOME)/agda-stdlib-$(AGDA_STDLIB_VERSION)/standard-library.agda-lib" >> $(HOME)/.agda/libraries
	echo "$(PLFA_DIR)/plfa.agda-lib" >> $(HOME)/.agda/libraries

$(HOME)/.local/bin/agda:
	curl -L https://github.com/agda/agda/archive/v$(AGDA_VERSION).zip -o $(HOME)/agda-$(AGDA_VERSION).zip
	unzip -qq $(HOME)/agda-$(AGDA_VERSION).zip -d $(HOME)
	cd $(HOME)/agda-$(AGDA_VERSION);\
		stack install --stack-yaml=stack-8.0.2.yaml

lua_modules/share/lua/$(LUA_VERSION)/cjson:
# Only this particular version works:
# https://github.com/mpx/lua-cjson/issues/56:
	luarocks install --tree lua_modules lua-cjson 2.1.0-1
	luarocks install --tree lua_modules liquid

lua_modules/share/lua/$(LUA_VERSION)/tinyyaml.lua:
	luarocks install --tree lua_modules lua-tinyyaml

lua_modules/share/lua/$(LUA_VERSION)/liquid.lua:
	luarocks install --tree lua_modules liquid

travis-uninstall-agda:
	rm -rf $(HOME)/agda-$(AGDA_VERSION)/
	rm -f $(HOME)/.local/bin/agda
	rm -f $(HOME)/.local/bin/agda-mode

travis-reinstall-agda: travis-uninstall-agda travis-install-agda

.phony: travis-install-agda travis-uninstall-agda travis-reinstall-agda


travis-install-agda-stdlib: $(HOME)/agda-stdlib-$(AGDA_STDLIB_VERSION)/src

$(HOME)/agda-stdlib-$(AGDA_STDLIB_VERSION)/src:
	curl -L https://github.com/agda/agda-stdlib/archive/v$(AGDA_STDLIB_VERSION).zip -o $(HOME)/agda-stdlib-$(AGDA_STDLIB_VERSION).zip
	unzip -qq $(HOME)/agda-stdlib-$(AGDA_STDLIB_VERSION).zip -d $(HOME)
	mkdir -p $(HOME)/.agda

travis-uninstall-agda-stdlib:
	rm $(HOME)/.agda/defaults
	rm $(HOME)/.agda/libraries
	rm -rf $(HOME)/agda-stdlib-$(AGDA_STDLIB_VERSION)/

travis-reinstall-agda-stdlib: travis-uninstall-agda-stdlib travis-install-agda-stdlib

.phony: travis-install-agda-stdlib travis-uninstall-agda-stdlib travis-reinstall-agda-stdlib epub
