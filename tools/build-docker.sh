#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# USAGE:
#    ./tools/build-docker.sh [TARGET]...
#    ./tools/build-docker.sh target-list

cd "$(cd "$(dirname "$0")" && pwd)"/..

x() {
    local cmd="$1"
    shift
    if [[ -n "${dry_run:-}" ]]; then
        (
            IFS=' '
            echo "+ $cmd $*"
        )
    else
        (
            set -x
            "$cmd" "$@"
        )
    fi
}

if [[ "${1:-}" == "-"* ]]; then
    cat <<EOF
USAGE:
    $0 [TARGET]...
    $0 target-list
EOF
    exit 1
fi
# shellcheck disable=SC1091
. tools/target-list-shared.sh
if [[ "${1:-}" == "target-list" ]]; then
    for target in "${targets[@]}"; do
        echo "${target}"
    done
    exit 0
fi
if [[ $# -gt 0 ]]; then
    targets=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) dry_run=1 ;;
            -*) echo >&2 "error: unknown argument '$1'" && exit 1 ;;
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
fi
if [[ ${#targets[@]} -eq 0 ]]; then
    echo >&2 "error: no target to build"
    exit 1
fi

export DOCKER_BUILDKIT=1
export BUILDKIT_STEP_LOG_MAX_SIZE=10485760

owner="${OWNER:-taiki-e}"
repository="ghcr.io/${owner}/rust-cross-toolchain"
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
    *) echo >&2 "error: unsupported architecture '${arch}'" && exit 1 ;;
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

    local dockerfile="docker/${base}.Dockerfile"
    local build_args=(
        --file "${dockerfile}" docker/
        --platform "${platform}"
        --build-arg "RUST_TARGET=${target}"
    )
    local tag="${repository}:${target}"
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
            build_args+=(--tag "${tag}-${github_tag}")
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
    echo "info: build log saved at ${log_dir}/build-docker-${time}.log"
}

for target in "${targets[@]}"; do
    case "${target}" in
        *-linux-gnu*)
            # NOTE: g++-powerpc-linux-gnuspe is not available in ubuntu 20.04 because GCC 9 removed support for this target: https://gcc.gnu.org/gcc-8/changes.html.
            ubuntu_version=18.04
            case "${target}" in
                # g++-mipsisa(32|64)r6(el)-linux-gnu(abi64) is not available in ubuntu 18.04.
                mipsisa32r6* | mipsisa64r6*) ubuntu_version=20.04 ;;
            esac
            build "linux-gnu" "${target}" \
                --build-arg "UBUNTU_VERSION=${ubuntu_version}"
            ;;
        *-linux-musl*)
            if [[ -n "${MUSL_VERSION:-}" ]]; then
                musl_versions=("${MUSL_VERSION}")
            else
                # https://musl.libc.org/releases.html
                # https://github.com/rust-lang/libc/issues/1848
                # When updating this, the reminder to update docker/base/build-docker.sh.
                musl_versions=("1.1" "1.2")
            fi
            default_musl_version=1.1
            for musl_version in "${musl_versions[@]}"; do
                case "${target}" in
                    hexagon-*)
                        default_musl_version=1.2
                        if [[ "${musl_version}" != "${default_musl_version}" ]]; then
                            continue
                        fi
                        build "linux-musl" "${target}" "${musl_version}" "${default_musl_version}"
                        ;;
                    *)
                        build "linux-musl" "${target}" "${musl_version}" "${default_musl_version}" \
                            --build-arg "MUSL_VERSION=${musl_version}"
                        ;;
                esac
            done
            ;;
        *-linux-uclibc*) build "linux-uclibc" "${target}" ;;
        *-android*) build "android" "${target}" ;;
        *-freebsd*)
            if [[ -n "${FREEBSD_VERSION:-}" ]]; then
                freebsd_versions=("${FREEBSD_VERSION}")
            else
                # FreeBSD have binary compatibility with previous releases.
                # Therefore, the default is FreeBSD 12 that is the minimum supported version.
                # However, we don't support FreeBSD 12 for the following targets, because:
                # - powerpc,powerpc64: FreeBSD 12 uses gcc instead of clang.
                # - powerpc64le,riscv64: not available in FreeBSD 12.
                # See also https://www.freebsd.org/releases/13.0R/announce.
                #
                # Supported releases: https://www.freebsd.org/security/#sup
                # FreeBSD 11 was EoL on 2021-9-30.
                # https://www.freebsd.org/security/unsupported
                # TODO: update 12.2 to 12.3 on 2022-4: 12.2 will be EoL on 2022-3-31
                freebsd_versions=("12.2" "13.0")
            fi
            default_freebsd_version=12
            for freebsd_version in "${freebsd_versions[@]}"; do
                case "${target}" in
                    powerpc-* | powerpc64-* | powerpc64le-* | riscv64gc-*)
                        default_freebsd_version=13
                        if [[ "${freebsd_version}" == "12"* ]]; then
                            continue
                        fi
                        ;;
                esac
                build "freebsd" "${target}" "${freebsd_version%%.*}" "${default_freebsd_version}" \
                    --build-arg "FREEBSD_VERSION=${freebsd_version}"
            done
            ;;
        *-netbsd*)
            if [[ -n "${NETBSD_VERSION:-}" ]]; then
                netbsd_versions=("${NETBSD_VERSION}")
            else
                # NetBSD have binary compatibility with previous releases.
                # Therefore, the default is NetBSD 8 that is the minimum supported version.
                # However, we don't support NetBSD 8 for the following targets, because:
                # - aarch64: not available in NetBSD 8.
                # See also https://www.netbsd.org/releases/formal-9/NetBSD-9.0.html.
                #
                # Supported releases: https://www.netbsd.org/releases
                # NetBSD 7 was EoL on 2020-6-30.
                # https://www.netbsd.org/releases/formal.html
                netbsd_versions=("8" "9")
            fi
            default_netbsd_version=8
            for netbsd_version in "${netbsd_versions[@]}"; do
                case "${target}" in
                    aarch64-*)
                        default_netbsd_version=9
                        if [[ "${netbsd_version}" == "8"* ]]; then
                            continue
                        fi
                        ;;
                esac
                build "netbsd" "${target}" "${netbsd_version%%.*}" "${default_netbsd_version}" \
                    --build-arg "NETBSD_VERSION=${netbsd_version}"
            done
            ;;
        *-openbsd*)
            # OpenBSD does not have binary compatibility with previous releases.
            # For now, we select the oldest supported version as default version.
            # However, we don't support OpenBSD 6.9, because there is no
            # libexecinfo.* in binary distribution sets.
            # https://github.com/rust-lang/libc/issues/570
            # https://github.com/golang/go/issues/15227
            # https://github.com/golang/go/wiki/OpenBSD
            # https://github.com/golang/go/wiki/MinimumRequirements#openbsd
            # The latest two releases are supported.
            # https://www.openbsd.org/faq/faq5.html#Flavors
            # https://en.wikipedia.org/wiki/OpenBSD#Releases
            openbsd_version="${OPENBSD_VERSION:-"7.0"}"
            default_openbsd_version="7.0"
            build "openbsd" "${target}" "${openbsd_version}" "${default_openbsd_version}" \
                --build-arg "OPENBSD_VERSION=${openbsd_version}"
            ;;
        *-dragonfly*)
            # https://mirror-master.dragonflybsd.org/iso-images
            dragonfly_version="${DRAGONFLY_VERSION:-"6.0.1"}"
            default_dragonfly_version=6
            build "dragonfly" "${target}" "${dragonfly_version%%.*}" "${default_dragonfly_version}" \
                --build-arg "DRAGONFLY_VERSION=${dragonfly_version}"
            ;;
        *-solaris*) build "solaris" "${target}" ;;
        *-illumos*) build "illumos" "${target}" ;;
        *-redox*) build "redox" "${target}" ;;
        *-fuchsia*) build "fuchsia" "${target}" ;;
        *-wasi*) build "wasi" "${target}" ;;
        *-emscripten*) build "emscripten" "${target}" ;;
        *-windows-gnu*) build "windows-gnu" "${target}" ;;
        *) echo >&2 "error: unrecognized target '${target}'" && exit 1 ;;
    esac
done

x docker images "${repository}"
