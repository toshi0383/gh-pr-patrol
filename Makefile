.PHONY = clean update build test bootstrap
SOURCERY ?= sourcery # Please install appropriate version on your own.
CMDSHELF ?= cmdshelf

clean:
	rm -rf .build
	rm Package.resolved

update:
	swift package update

build:
	swift build

bootstrap: build
	swift package generate-xcodeproj

# Needs toshi0383/scripts to be added to cmdshelf's remote
install:
	$(CMDSHELF) run swiftpm/install.sh toshi0383/gh-pr-patrol

release:
	rm -rf .build/release
	swift build -c release -Xswiftc -static-stdlib
	$(CMDSHELF) run swiftpm/release.sh gh-pr-patrol
