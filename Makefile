APP = .build/Breeze for Dreo.app

.PHONY: build install release test strings demo clean

build:      ## Build the app for this Mac
	scripts/build.sh

install:    ## Build and install to /Applications
	scripts/build.sh --install

release:    ## Universal build + zip, as published on GitHub
	scripts/build.sh --universal --zip

test:       ## Run the tests (demo backend, no account needed)
	scripts/test.sh

strings:    ## List strings missing a translation
	scripts/check-strings.sh

demo: build ## Try the app with fake fans
	"$(APP)/Contents/MacOS/Breeze" --demo

clean:
	rm -rf .build
