#!/usr/bin/env bash
# detect_stack.sh [repo-root]
# Sniff a project's language/test tooling and print candidate test commands,
# single-test syntax, and test-file conventions. Prefer the project's own
# documented command (CLAUDE.md, README, CI config) over these guesses.
set -u
root="${1:-.}"
cd "$root" || { echo "no such directory: $root" >&2; exit 1; }

found=0
hit() { # hit <label> <run-all> <run-one> <convention>
  found=1
  printf '%s\n  all:  %s\n  one:  %s\n  conv: %s\n' "$1" "$2" "$3" "$4"
}

if [ -f Makefile ] && grep -qE '^test[[:space:]]*:' Makefile; then
  hit "Makefile" "make test" "(see Makefile for filtering)" "project-defined; prefer this entry point"
fi
if [ -f Justfile ] || [ -f justfile ]; then
  if grep -qiE '^test' Justfile justfile 2>/dev/null; then
    hit "Justfile" "just test" "(see Justfile)" "project-defined; prefer this entry point"
  fi
fi
if [ -f go.mod ] || [ -f go.work ]; then
  hit "Go" "go test ./..." "go test ./path/to/pkg -run 'TestName' -v" "*_test.go next to the code; table-driven idiomatic; add -race for races"
fi
if [ -f Cargo.toml ]; then
  hit "Rust" "cargo test" "cargo test test_name -- --exact --nocapture" "#[test] in src (unit) or tests/ (integration)"
fi
if [ -f package.json ]; then
  runner="npm"
  [ -f pnpm-lock.yaml ] && runner="pnpm"
  [ -f yarn.lock ] && runner="yarn"
  [ -f bun.lockb ] || [ -f bun.lock ] && runner="bun"
  script=$(sed -n 's/.*"test"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' package.json | head -1)
  fw="(check devDependencies: vitest/jest/mocha/node:test/playwright)"
  grep -q '"vitest"' package.json && fw="vitest run path -t 'name'"
  grep -q '"jest"' package.json && fw="jest path -t 'name'"
  grep -q '"mocha"' package.json && fw="mocha path --grep 'name'"
  hit "JS/TS ($runner)" "$runner test${script:+  # runs: $script}" "$fw" "*.test.* / *.spec.* / __tests__/"
fi
if [ -f pyproject.toml ] || [ -f setup.py ] || [ -f pytest.ini ] || [ -f setup.cfg ] || [ -f tox.ini ]; then
  hit "Python" "pytest" "pytest path/to/test_file.py::test_name -x -vv" "test_*.py under tests/ or beside code; uv run pytest if uv-managed"
fi
if [ -f CMakeLists.txt ]; then
  hit "C/C++ (CMake)" "ctest --test-dir <build-dir> --output-on-failure" "ctest --test-dir <build-dir> -R 'name' --output-on-failure" "add_test() in CMakeLists; set TIMEOUT on hang-prone tests"
fi
if [ -f Gemfile ]; then
  fw="bundle exec rake test"
  grep -q 'rspec' Gemfile && fw="bundle exec rspec"
  hit "Ruby" "$fw" "bundle exec rspec path:LINE  (or ruby -Itest path -n /name/)" "spec/**/*_spec.rb or test/**/*_test.rb"
fi
if [ -f pom.xml ]; then
  hit "Java (Maven)" "mvn test" "mvn test -Dtest='ClassName#method'" "src/test/java/**/*Test.java"
fi
if [ -f build.gradle ] || [ -f build.gradle.kts ]; then
  hit "JVM (Gradle)" "./gradlew test" "./gradlew test --tests 'pkg.ClassName.method'" "src/test/{java,kotlin}"
fi
if [ -f Package.swift ]; then
  hit "Swift (SPM)" "swift test" "swift test --filter 'SuiteName/testName'" "Tests/<Target>Tests/; swift-testing or XCTest"
fi
if ls -d ./*.xcodeproj ./*.xcworkspace >/dev/null 2>&1; then
  hit "Xcode" "xcodebuild test -scheme <Scheme> -destination 'platform=macOS'" "add -only-testing:Target/Suite (suite-level is reliable; function-level often is not)" "check for a Makefile/fastlane wrapper first"
fi
if [ -f mix.exs ]; then
  hit "Elixir" "mix test" "mix test path/to/test.exs:LINE" "test/**/*_test.exs"
fi
if [ -f composer.json ]; then
  hit "PHP" "vendor/bin/phpunit" "vendor/bin/phpunit --filter 'testName' path" "tests/**/*Test.php"
fi
if ls ./*.sln ./*.csproj >/dev/null 2>&1 || ls ./*/*.csproj >/dev/null 2>&1; then
  hit ".NET" "dotnet test" "dotnet test --filter 'FullyQualifiedName~Name'" "*Tests.csproj projects"
fi
if [ -f deno.json ] || [ -f deno.jsonc ]; then
  hit "Deno" "deno test" "deno test path --filter 'name'" "*_test.ts / *.test.ts"
fi

# CI configs often hold the authoritative test invocation.
for ci in .github/workflows/*.yml .github/workflows/*.yaml .gitlab-ci.yml .circleci/config.yml; do
  [ -f "$ci" ] || continue
  lines=$(grep -hE '^[[:space:]]*(run|script)[[:space:]:>|-]' "$ci" 2>/dev/null | grep -iE 'test' | head -5)
  if [ -n "$lines" ]; then
    found=1
    printf 'CI (%s) test-ish steps:\n%s\n' "$ci" "$lines"
  fi
done

if [ "$found" -eq 0 ]; then
  echo "No known test tooling detected in $root — read README/CLAUDE.md/CI config."
  exit 1
fi
