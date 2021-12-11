#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# USAGE:
#    ./docker/base/build-docker.sh <TARGET>

cd "$(cd "$(dirname "$0")" && pwd)"/../..

if [[ $# -ne 1 ]]; then
    cat <<EOF
USAGE:
    $0 <TARGET>
EOF
    exit 1
fi
set -x
target="$1"

export DOCKER_BUILDKIT=1
export BUILDKIT_STEP_LOG_MAX_SIZE=10485760

owner="${OWNER:-taiki-e}"
registry="ghcr.io/${owner}"
tag_base="${registry}/rust-cross-toolchain:"
arch="${HOST_ARCH:-amd64}"
case "${arch}" in
    amd64)
        full_arch=amd64
        platform=linux/amd64
        ;;
    arm64)
        full_arch=arm64v8
        platform=linux/arm64/v8
        ;;
    *) echo >&2 "unsupported architecture '${arch}'" && exit 1 ;;
esac
time="$(date --utc '+%Y-%m-%d-%H-%M-%S')"

github_tag="dev"
if [[ "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
    github_tag="${GITHUB_REF_NAME}"
fi

__build() {
    local tag="$1"
    shift

    if [[ -n "${PUSH_TO_GHCR:-}" ]]; then
        docker buildx build --push "$@" || (echo "build log saved at ${log_dir}/build-docker-${time}.log" && exit 1)
        docker pull "${tag}"
        docker history "${tag}"
    else
        docker buildx build --load "$@" || (echo "build log saved at ${log_dir}/build-docker-${time}.log" && exit 1)
        docker history "${tag}"
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
    local tag="${tag_base}${target}"
    log_dir="tmp/log/base/${base}/${target}"
    if [[ "${1:-}" =~ ^[0-9]+.* ]]; then
        local sys_version="$1"
        shift
        local tag="${tag}${sys_version}"
        log_dir="${log_dir}${sys_version}"
    fi
    local tag="${tag}-base-${github_tag}-${full_arch}"
    build_args+=(--tag "${tag}")

    mkdir -p "${log_dir}"
    __build "${tag}" "${build_args[@]}" "$@" 2>&1 | tee "${log_dir}/build-docker-${time}.log"
    echo "build log saved at ${log_dir}/build-docker-${time}.log"
}

case "${target}" in
    hexagon-unknown-linux-musl) build "linux-musl-hexagon" "${target}" ;;
    *-linux-musl*) build "linux-musl" "${target}" ;;
    *-solaris*) build "solaris" "${target}" ;;
    *-illumos*) build "illumos" "${target}" ;;
    *-windows-gnu*) build "windows-gnu" "${target}" ;;
    *) echo >&2 "unrecognized target '${target}'" && exit 1 ;;
esac
