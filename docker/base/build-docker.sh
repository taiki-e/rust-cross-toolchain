#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# USAGE:
#    ./docker/base/build-docker.sh <TARGET>

cd "$(cd "$(dirname "$0")" && pwd)"/../..

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
time="$(date --utc '+%Y-%m-%d-%H-%M-%S')"

github_tag="dev"
if [[ "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
    github_tag="${GITHUB_REF_NAME#base-}"
fi

__build() {
    local tag="$1"
    shift

    if [[ -n "${PUSH_TO_GHCR:-}" ]]; then
        x docker buildx build --push "$@" || (echo "info: build log saved at ${log_dir}/build-docker-${time}.log" && exit 1)
        x docker pull "${tag}"
        x docker history "${tag}"
    else
        x docker buildx build --load "$@" || (echo "info: build log saved at ${log_dir}/build-docker-${time}.log" && exit 1)
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
        local tag="${tag}${sys_version}"
        log_dir="${log_dir}${sys_version}"
    fi
    local tag="${tag}-base-${github_tag}-${docker_arch}"
    build_args+=(--tag "${tag}")

    mkdir -p "${log_dir}"
    __build "${tag}" "${build_args[@]}" "$@" 2>&1 | tee "${log_dir}/build-docker-${time}.log"
    echo "info: build log saved at ${log_dir}/build-docker-${time}.log"
}

case "${target}" in
    hexagon-unknown-linux-musl) build "linux-musl-hexagon" "${target}" ;;
    *-linux-musl*)
        if [[ -n "${MUSL_VERSION:-}" ]]; then
            musl_versions=("${MUSL_VERSION}")
        else
            # See tools/build-docker.sh for more.
            musl_versions=("1.1.24" "1.2.2")
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
            # See tools/build-docker.sh for more.
            netbsd_versions=("8.2" "9.2")
        fi
        for netbsd_version in "${netbsd_versions[@]}"; do
            case "${target}" in
                aarch64-*)
                    if [[ "${netbsd_version}" == "8"* ]]; then
                        continue
                    fi
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
