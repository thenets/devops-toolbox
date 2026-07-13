# Bash patterns

Use only the patterns the task needs. Adapt names and interfaces to the host
repository.

## Resolve the script directory

Use `BASH_SOURCE[0]`, not the caller's working directory:

```bash
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
```

## Support sourcing and direct execution

Define functions without running the program when sourced:

```bash
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
```

## Print stable help text

Prefer an explicit heredoc over extracting comments from the file. It is easier
to review and does not couple documentation to source layout:

```bash
usage() {
    cat <<EOF
Usage: ${0##*/} [OPTIONS] FILE
  -h, --help  Show help
EOF
}
```

## Detect terminal output

Use `[[ -t 1 ]]` for stdout and `[[ -t 2 ]]` for stderr. A pipe or redirection
is simply the non-terminal case; avoid testing `/dev/stdout` file types.

```bash
if [[ -t 2 ]] && command -v tput >/dev/null 2>&1; then
    readonly RED="$(tput setaf 1)"
    readonly RESET="$(tput sgr0)"
else
    readonly RED=''
    readonly RESET=''
fi
```

## Clean up temporary resources

Create private temporary directories and make cleanup safe to call repeatedly:

```bash
temp_dir=''

cleanup() {
    [[ -z ${temp_dir} ]] || rm -rf -- "${temp_dir}"
}

trap cleanup EXIT
temp_dir=$(mktemp -d)
```

For sensitive data, verify the platform's `mktemp` permissions and never log the
contents or secret-bearing path.

## Retry a command with a bound

Accept the command as an argument array. Do not use `eval`:

```bash
retry() {
    local max_attempts=$1
    local delay=$2
    shift 2
    local attempt

    for ((attempt = 1; attempt <= max_attempts; attempt++)); do
        if "$@"; then
            return 0
        fi
        if ((attempt < max_attempts)); then
            printf 'Attempt %d/%d failed; retrying in %ss\n' \
                "${attempt}" "${max_attempts}" "${delay}" >&2
            sleep "${delay}"
        fi
    done

    return 1
}

retry 5 2 curl --fail --silent --show-error https://example.com/health
```

Choose a readiness check that proves the required service works; network reachability
alone may be insufficient.
