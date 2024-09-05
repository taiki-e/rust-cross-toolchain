#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0 OR MIT
set -eEuo pipefail
IFS=$'\n\t'
cd "$(dirname "$0")"/../..

# shellcheck disable=SC2154
trap 's=$?; echo >&2 "$0: error on line "${LINENO}": ${BASH_COMMAND}"; exit ${s}' ERR

# USAGE:
#    ./docker/base/build-docker.sh <TARGET>

x() {
    local cmd="$1"
    shift
    (
        set -x
        "${cmd}" "$@"
    )
}

if [[ "${1:-}" == "-"* ]] || [[ $# -ne 1 ]]; then
    cat <<EOF
USAGE:
    $0 <TARGET>
EOF
    exit 1
fi
target="$1"

export DOCKER_BUILDKIT=1
export BUILDKIT_STEP_LOG_MAX_SIZE=10485760

owner="${OWNER:-taiki-e}"
repository="ghcr.io/${owner}/rust-cross-toolchain"
arch="${HOST_ARCH:-"$(uname -m)"}"
case "${arch}" in
    x86_64 | x86-64 | x64 | amd64)
        arch=x86_64
        docker_arch=amd64
        platform=linux/amd64
        ;;
    aarch64 | arm64)
        arch=aarch64
        docker_arch=arm64v8
        platform=linux/arm64/v8
        ;;
    *) echo >&2 "error: unsupported architecture '${arch}'" && exit 1 ;;
esac
time=$(date -u '+%Y-%m-%d-%H-%M-%S')

github_tag="dev"
if [[ "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
    github_tag="${GITHUB_REF_NAME#base-}"
fi

__build() {
    local tag="$1"
    shift

    if [[ -n "${PUSH_TO_GHCR:-}" ]]; then
        x docker buildx build --provenance=false --push "$@" || (echo "info: build log saved at ${log_dir}/build-docker-${time}.log" && exit 1)
        x docker pull "${tag}"
        x docker history "${tag}"
    else
        x docker buildx build --provenance=false --load "$@" || (echo "info: build log saved at ${log_dir}/build-docker-${time}.log" && exit 1)
        x docker history "${tag}"
    fi
}

build() {
    local base="$1"
    local target="$2"
    shift
    shift

    local dockerfile="docker/base/${base}.Dockerfile"
    local build_args=(
        --file "${dockerfile}" docker/base
        --platform "${platform}"
        --build-arg "RUST_TARGET=${target}"
    )
    local tag="${repository}:${target}"
    log_dir="tmp/log/base/${base}/${target}"
    if [[ "${1:-}" =~ ^[0-9]+.* ]]; then
        local sys_version="$1"
        shift
        tag+="${sys_version}"
        log_dir+="${sys_version}"
    fi
    tag+="-base-${github_tag}-${docker_arch}"
    build_args+=(--tag "${tag}")

    mkdir -p "${log_dir}"
    __build "${tag}" "${build_args[@]}" "$@" 2>&1 | tee "${log_dir}/build-docker-${time}.log"
    echo "info: build log saved at ${log_dir}/build-docker-${time}.log"
}

case "${target}" in
    hexagon-unknown-linux-musl)
        musl_version=1.2
        build "linux-musl-hexagon" "${target}" "${musl_version}"
        ;;
    *-linux-musl*)
        if [[ -n "${MUSL_VERSION:-}" ]]; then
            musl_versions=("${MUSL_VERSION}")
        else
            # NB: When updating this, the reminder to update tools/build-docker.sh.
            musl_versions=(
                # "1.1.24"
                "1.2.3"
            )
        fi
        for musl_version in "${musl_versions[@]}"; do
            build "linux-musl" "${target}" "${musl_version%.*}" \
                --build-arg "MUSL_VERSION=${musl_version}"
        done
        ;;
    *-netbsd*)
        if [[ -n "${NETBSD_VERSION:-}" ]]; then
            netbsd_versions=("${NETBSD_VERSION}")
        else
            # NB: When updating this, the reminder to update tools/build-docker.sh.
            netbsd_versions=("9.4" "10.0")
        fi
        for netbsd_version in "${netbsd_versions[@]}"; do
            case "${target}" in
                aarch64-*)
                    case "${netbsd_version}" in
                        8.*) continue ;;
                    esac
                    ;;
                aarch64_be-*)
                    case "${netbsd_version}" in
                        [8-9].*) continue ;;
                    esac
                    ;;
            esac
            build "netbsd" "${target}" "${netbsd_version%%.*}" \
                --build-arg "NETBSD_VERSION=${netbsd_version}"
        done
        ;;
    *-solaris*) build "solaris" "${target}" ;;
    *-illumos*) build "illumos" "${target}" ;;
    *-windows-gnu*) build "windows-gnu" "${target}" ;;
    various)
        targets=(
            aarch64-none-elf
            arm-none-eabi
            riscv32-unknown-elf
            riscv64-unknown-elf
        )
        for target in "${targets[@]}"; do
            case "${target}" in
                riscv*)
                    # Toolchains for these targets are not available on non-x86_64 host.
                    case "${arch}" in
                        x86_64) ;;
                        *) continue ;;
                    esac
                    ;;
            esac
            build "various" "${target}" --build-arg "TARGET=${target}"
        done
        ;;
    *) echo >&2 "error: unrecognized target '${target}'" && exit 1 ;;
esac

x docker images "${repository}"
