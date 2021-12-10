#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

cd "$(cd "$(dirname "$0")" && pwd)"/..

if [[ "${1:-}" == "-"* ]]; then
    cat <<EOF
USAGE:
    $0 [TARGET]..
    $0 target-list
EOF
    exit 1
fi
if [[ "${1:-}" == "target-list" ]]; then
    # shellcheck disable=SC1091
    . tools/target-list.sh
    for target in "${targets[@]}"; do
        echo "${target}"
    done
    exit 0
fi
set -x
if [[ $# -gt 0 ]]; then
    # shellcheck disable=SC1091
    . tools/target-list.sh
    targets=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            linux-gnu) targets+=(${linux_gnu_targets[@]+"${linux_gnu_targets[@]}"}) ;;
            linux-musl) targets+=(${linux_musl_targets[@]+"${linux_musl_targets[@]}"}) ;;
            linux-uclibc) targets+=(${linux_uclibc_targets[@]+"${linux_uclibc_targets[@]}"}) ;;
            android) targets+=(${android_targets[@]+"${android_targets[@]}"}) ;;
            freebsd) targets+=(${freebsd_targets[@]+"${freebsd_targets[@]}"}) ;;
            netbsd) targets+=(${netbsd_targets[@]+"${netbsd_targets[@]}"}) ;;
            openbsd) targets+=(${openbsd_targets[@]+"${openbsd_targets[@]}"}) ;;
            dragonfly) targets+=(${dragonfly_targets[@]+"${dragonfly_targets[@]}"}) ;;
            solaris) targets+=(${solaris_targets[@]+"${solaris_targets[@]}"}) ;;
            illumos) targets+=(${illumos_targets[@]+"${illumos_targets[@]}"}) ;;
            redox) targets+=(${redox_targets[@]+"${redox_targets[@]}"}) ;;
            fuchsia) targets+=(${fuchsia_targets[@]+"${fuchsia_targets[@]}"}) ;;
            wasi) targets+=(${wasi_targets[@]+"${wasi_targets[@]}"}) ;;
            emscripten) targets+=(${emscripten_targets[@]+"${emscripten_targets[@]}"}) ;;
            windows-gnu) targets+=(${windows_gnu_targets[@]+"${windows_gnu_targets[@]}"}) ;;
            *) targets+=("$1") ;;
        esac
        shift
    done
else
    # shellcheck disable=SC1091
    . tools/target-list.sh
fi
if [[ ${#targets[@]} -eq 0 ]]; then
    echo >&2 "no target to build"
    exit 1
fi

export DOCKER_BUILDKIT=1
export BUILDKIT_STEP_LOG_MAX_SIZE=10485760

owner="${OWNER:-taiki-e}"
tag_base="ghcr.io/${owner}/rust-cross-toolchain:"
arch="${HOST_ARCH:-amd64}"
case "${arch}" in
    amd64)
        # full_arch=amd64
        platform=linux/amd64
        ;;
    arm64)
        # full_arch=arm64v8
        platform=linux/arm64/v8
        ;;
    *) echo >&2 "unsupported architecture '${arch}'" && exit 1 ;;
esac
time="$(date --utc '+%Y-%m-%d-%H-%M-%S')"

github_tag="dev"
is_release=""
if [[ "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
    github_tag="${GITHUB_REF_NAME}"
    is_release=1
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

    local dockerfile="docker/${base}.Dockerfile"
    local build_args=(
        --file "${dockerfile}" docker/
        --platform "${platform}"
        --build-arg "RUST_TARGET=${target}"
    )
    local tag="${tag_base}${target}"
    log_dir="tmp/log/${base}/${target}"
    if [[ "${1:-}" =~ ^[0-9]+.* ]]; then
        local sys_version="$1"
        local default_sys_version="$2"
        shift
        shift
        if [[ "${sys_version}" == "${default_sys_version}" ]]; then
            if [[ -n "${is_release}" ]]; then
                build_args+=(--tag "${tag}")
            fi
            local tag="${tag}-${github_tag}"
            build_args+=(--tag "${tag}")
        fi
        local tag="${tag}${sys_version}"
        log_dir="${log_dir}${sys_version}"
    fi
    if [[ -n "${is_release}" ]]; then
        build_args+=(--tag "${tag}")
    fi
    local tag="${tag}-${github_tag}"
    build_args+=(--tag "${tag}")

    mkdir -p "${log_dir}"
    __build "${tag}" "${build_args[@]}" "$@" 2>&1 | tee "${log_dir}/build-docker-${time}.log"
    echo "build log saved at ${log_dir}/build-docker-${time}.log"
}

for target in "${targets[@]}"; do
    case "${target}" in
        *-linux-gnu*)
            case "${target}" in
                # g++-mipsisa(32|64)r6(el)-linux-gnu(abi64) is not available in ubuntu 18.04.
                mipsisa32r6* | mipsisa64r6*) ubuntu_version=20.04 ;;
                # NOTE: g++-powerpc-linux-gnuspe is not available in ubuntu 20.04 because GCC 9 removed support for this target: https://gcc.gnu.org/gcc-8/changes.html.
                *) ubuntu_version=18.04 ;;
            esac
            build_args=(--build-arg "UBUNTU_VERSION=${ubuntu_version}")
            build "linux-gnu" "${target}" "${build_args[@]}"
            ;;
        *-linux-musl*) build "linux-musl" "${target}" ;;
        *-linux-uclibc*) build "linux-uclibc" "${target}" ;;
        *-android*) build "android" "${target}" ;;
        *-freebsd*)
            # FreeBSD have binary compatibility with previous releases.
            # Therefore, the default is FreeBSD 12 that is the minimum supported version.
            # However, for powerpc* and riscv64 targets, we use freebsd 13, because:
            # - powerpc/powerpc64: freebsd 12 uses gcc instead of clang.
            # - powerpc64le/riscv64: not available in freebsd 12.
            # See also: https://www.freebsd.org/releases/13.0R/announce
            # https://www.freebsd.org/security/#sup
            # https://www.freebsd.org/releases/12.3R/schedule
            for freebsd_version in "12.2" "13.0"; do
                build_args=(--build-arg "FREEBSD_VERSION=${freebsd_version}")
                case "${target}" in
                    aarch64-* | i686-* | x86_64-*)
                        build "freebsd" "${target}" "${freebsd_version%%.*}" "12" "${build_args[@]}"
                        ;;
                    powerpc-* | powerpc64-* | powerpc64le-* | riscv64gc-*)
                        if [[ "${freebsd_version}" == "12"* ]]; then
                            continue
                        fi
                        build "freebsd" "${target}" "${freebsd_version%%.*}" "13" "${build_args[@]}"
                        ;;
                    *) echo >&2 "unrecognized target '${target}'" && exit 1 ;;
                esac
            done
            ;;
        *-netbsd*) build "netbsd" "${target}" ;;
        *-openbsd*) build "openbsd" "${target}" ;;
        *-dragonfly*) build "dragonfly" "${target}" ;;
        *-solaris*) build "solaris" "${target}" ;;
        *-illumos*) build "illumos" "${target}" ;;
        *-redox*) build "redox" "${target}" ;;
        *-fuchsia*) build "fuchsia" "${target}" ;;
        *-wasi*) build "wasi" "${target}" ;;
        *-emscripten*) build "emscripten" "${target}" ;;
        *-windows-gnu*) build "windows-gnu" "${target}" ;;
        *) echo >&2 "unrecognized target '${target}'" && exit 1 ;;
    esac
done
