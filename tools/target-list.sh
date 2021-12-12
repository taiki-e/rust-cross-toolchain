#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# shellcheck disable=SC2207
rustup_targets=($(rustup target list | sed 's/ .*//g'))
# shellcheck disable=SC2207
all_targets=($(rustc --print target-list | sed 's/ .*//g'))
# https://doc.rust-lang.org/nightly/rustc/platform-support.html#tier-1-with-host-tools
tier1_targets=(
    aarch64-unknown-linux-gnu
    i686-pc-windows-gnu
    i686-pc-windows-msvc
    i686-unknown-linux-gnu
    x86_64-apple-darwin
    x86_64-pc-windows-gnu
    x86_64-pc-windows-msvc
    x86_64-unknown-linux-gnu
)
case "${1:-}" in
    tier1 | t1)
        for target in "${tier1_targets[@]}"; do
            echo "${target}"
        done
        ;;
    tier2 | t2)
        for target in "${rustup_targets[@]}"; do
            for t in "${tier1_targets[@]}"; do
                if [[ "${target}" == "${t}" ]]; then
                    target=""
                    break
                fi
            done
            if [[ -n "${target}" ]]; then
                echo "${target}"
            fi
        done
        ;;
    tier3 | t3)
        for target in "${all_targets[@]}"; do
            for t in "${rustup_targets[@]}"; do
                if [[ "${target}" == "${t}" ]]; then
                    target=""
                    break
                fi
            done
            if [[ -n "${target}" ]]; then
                echo "${target}"
            fi
        done
        ;;
    all)
        for target in "${all_targets[@]}"; do
            echo "${target}"
        done
        ;;
    rustup | "")
        for target in "${rustup_targets[@]}"; do
            echo "${target}"
        done
        ;;
    *) echo >&2 "error: unknown argument '$1'" && exit 1 ;;
esac
