# Mirrors the CI lanes so local checks cannot diverge (#158).
FLUTTER := flutter
DART := dart

.PHONY: bootstrap format analyze test coverage coverage-check check \
        build-macos build-ios build-android build-linux shellcheck

bootstrap: ## flutter pub get
	$(FLUTTER) pub get --enforce-lockfile

format: ## CI format check
	$(DART) format --set-exit-if-changed lib test tool

analyze: ## CI static analysis
	$(FLUTTER) analyze

test: ## unit + widget tests (mocked contracts)
	$(FLUTTER) test --reporter expanded

coverage: ## tests with coverage report
	$(FLUTTER) test --coverage

coverage-check: coverage ## per-directory coverage floors
	$(DART) run tool/check_coverage.dart

check: format analyze test ## what the CI test lane enforces

shellcheck: ## lint shell scripts
	shellcheck scripts/*.sh .github/scripts/*.sh

build-macos:
	$(FLUTTER) build macos

build-ios:
	$(FLUTTER) build ios --no-codesign

build-android:
	$(FLUTTER) build apk --debug

build-linux:
	$(FLUTTER) build linux --release
