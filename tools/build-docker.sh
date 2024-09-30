#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0 OR MIT
set -eEuo pipefail
IFS=$'\n\t'
cd "$(dirname "$0")"/..

# shellcheck disable=SC2154
trap 's=$?; echo >&2 "$0: error on line "${LINENO}": ${BASH_COMMAND}"; exit ${s}' ERR

# USAGE:
#    ./tools/build-docker.sh [TARGET]...

x() {
    local cmd="$1"
    shift
    if [[ -n "${dry_run}" ]]; then
        (
            IFS=' '
            echo "+ ${cmd} $*"
        )
    else
        (
            set -x
            "${cmd}" "$@"
        )
    fi
}
bail() {
    echo >&2 "error: ${BASH_SOURCE[1]##*/}:${BASH_LINENO[0]}: $*"
    exit 1
}

if [[ "${1:-}" == "-"* ]]; then
    cat <<EOF
USAGE:
    $0 [TARGET]...
EOF
    exit 1
fi
# shellcheck disable=SC1091
. tools/target-list-shared.sh
dry_run=''
if [[ $# -gt 0 ]]; then
    targets=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) dry_run=1 ;;
            -*) bail "unknown argument '$1'" ;;
            linux-gnu) targets+=(${linux_gnu_targets[@]+"${linux_gnu_targets[@]}"}) ;;
            linux-musl) targets+=(${linux_musl_targets[@]+"${linux_musl_targets[@]}"}) ;;
            linux-uclibc) targets+=(${linux_uclibc_targets[@]+"${linux_uclibc_targets[@]}"}) ;;
            android) targets+=(${android_targets[@]+"${android_targets[@]}"}) ;;
            macos) targets+=(${macos_targets[@]+"${macos_targets[@]}"}) ;;
            ios) targets+=(${ios_targets[@]+"${ios_targets[@]}"}) ;;
            tvos) targets+=(${tvos_targets[@]+"${tvos_targets[@]}"}) ;;
            watchos) targets+=(${watchos_targets[@]+"${watchos_targets[@]}"}) ;;
            visionos) targets+=(${visionos_targets[@]+"${visionos_targets[@]}"}) ;;
            freebsd) targets+=(${freebsd_targets[@]+"${freebsd_targets[@]}"}) ;;
            netbsd) targets+=(${netbsd_targets[@]+"${netbsd_targets[@]}"}) ;;
            openbsd) targets+=(${openbsd_targets[@]+"${openbsd_targets[@]}"}) ;;
            dragonfly) targets+=(${dragonfly_targets[@]+"${dragonfly_targets[@]}"}) ;;
            solaris) targets+=(${solaris_targets[@]+"${solaris_targets[@]}"}) ;;
            illumos) targets+=(${illumos_targets[@]+"${illumos_targets[@]}"}) ;;
            windows-msvc) targets+=(${windows_msvc_targets[@]+"${windows_msvc_targets[@]}"}) ;;
            windows-gnu) targets+=(${windows_gnu_targets[@]+"${windows_gnu_targets[@]}"}) ;;
            wasi) targets+=(${wasi_targets[@]+"${wasi_targets[@]}"}) ;;
            emscripten) targets+=(${emscripten_targets[@]+"${emscripten_targets[@]}"}) ;;
            redox) targets+=(${redox_targets[@]+"${redox_targets[@]}"}) ;;
            fuchsia) targets+=(${fuchsia_targets[@]+"${fuchsia_targets[@]}"}) ;;
            none) targets+=(${none_targets[@]+"${none_targets[@]}"}) ;;
            *) targets+=("$1") ;;
        esac
        shift
    done
fi
if [[ ${#targets[@]} -eq 0 ]]; then
    bail "no target to build"
fi

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
    *) bail "unsupported host architecture '${arch}'" ;;
esac
case "$(uname -m)" in
    x86_64 | x86-64 | x64 | amd64) real_host_arch=x86_64 ;;
    aarch64 | arm64) real_host_arch=aarch64 ;;
    *) bail "unsupported host architecture '${arch}'" ;;
esac
time=$(date -u '+%Y-%m-%d-%H-%M-%S')

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

    local dockerfile="docker/${base}.Dockerfile"
    local build_args=(
        --file "${dockerfile}" docker/
        --platform "${platform}"
        --build-arg "RUST_TARGET=${target}"
        --build-arg "HOST_ARCH=${docker_arch}"
        --build-arg "REAL_HOST_ARCH=${real_host_arch}"
    )
    local tag="${repository}:${target}"
    log_dir="tmp/log/${base}/${target}"
    if [[ -n "${1:-}" ]] && [[ "${1:-}" != "--"* ]]; then
        local sys_version="$1"
        local default_sys_version="$2"
        shift
        shift
        if [[ "${sys_version}" == "${default_sys_version}" ]]; then
            if [[ -n "${is_release}" ]]; then
                build_args+=(--tag "${tag}-${docker_arch}")
            fi
            build_args+=(--tag "${tag}-${github_tag}-${docker_arch}")
        fi
        tag+="${sys_version}"
        log_dir+="${sys_version}"
    fi
    if [[ -n "${is_release}" ]]; then
        build_args+=(--tag "${tag}-${docker_arch}")
    fi
    tag+="-${github_tag}-${docker_arch}"
    build_args+=(--tag "${tag}")

    mkdir -p "${log_dir}"
    __build "${tag}" "${build_args[@]}" "$@" 2>&1 | tee "${log_dir}/build-docker-${time}.log"
    echo "info: build log saved at ${log_dir}/build-docker-${time}.log"
}

for target in "${targets[@]}"; do
    case "${target}" in
        *-linux-gnu*)
            ubuntu_version=18.04
            # NB: When updating this, the reminder to update tools/update-manifest.sh.
            case "${target}" in
                aarch64_be-* | armeb-* | arm-*hf | csky-* | loongarch64-* | riscv32* | powerpc64-* | powerpc-*spe)
                    # aarch64_be-*|armeb-*|arm-*hf|csky-*|loongarch64-*|riscv32*: Toolchains for these targets are not available on non-x86_64 host.
                    # powerpc64-*|powerpc-*spe: gcc-(powerpc64-linux-gnu|powerpc-linux-gnuspe) for arm64 host is not available on 24.04.
                    case "${arch}" in
                        x86_64) ;;
                        *) continue ;;
                    esac
                    ;;
            esac
            case "${target}" in
                # old file command doesn't support csky/loongarch64
                csky-* | loongarch64-*) ubuntu_version=22.04 ;;
            esac
            case "${arch}" in
                # Note: gcc-powerpc-linux-gnuspe is not available in ubuntu 20.04 because GCC 9 removed support for this target: https://gcc.gnu.org/gcc-8/changes.html.
                x86_64)
                    case "${target}" in
                        # g++-mipsisa(32|64)r6(el)-linux-gnu(abi64) is not available in ubuntu 18.04.
                        mipsisa32r6* | mipsisa64r6*) ubuntu_version=20.04 ;;
                    esac
                    ;;
                aarch64)
                    case "${target}" in
                        # gcc-(mips|mipsel|mips64|mips64el|mipsisa32r6|mipsisa32r6el)-linux-gnu for arm64 host is available on ubuntu 21.04+.
                        mips*) ubuntu_version=22.04 ;;
                        # gcc-(powerpc|sparc64)-linux-gnu for arm64 host is available on ubuntu 23.10+.
                        powerpc-* | sparc-* | sparc64-*) ubuntu_version=24.04 ;;
                    esac
                    ;;
            esac
            build "linux-gnu" "${target}" \
                --build-arg "DISTRO_VERSION=${ubuntu_version}"
            ;;
        *-linux-musl*)
            if [[ -n "${MUSL_VERSION:-}" ]]; then
                musl_versions=("${MUSL_VERSION}")
            else
                # https://musl.libc.org/releases.html
                # https://github.com/rust-lang/libc/issues/1848
                # NB: When updating this, the reminder to update docker/base/build-docker.sh and README.md.
                musl_versions=("1.1" "1.2")
            fi
            default_musl_version="1.1"
            for musl_version in "${musl_versions[@]}"; do
                case "${target}" in
                    hexagon-* | powerpc-*spe | riscv32*)
                        default_musl_version="1.2"
                        if [[ "${musl_version}" != "${default_musl_version}" ]]; then
                            continue
                        fi
                        ;;
                esac
                build "linux-musl" "${target}" "${musl_version}" "${default_musl_version}" \
                    --build-arg "MUSL_VERSION=${musl_version}"
            done
            ;;
        *-linux-uclibc*) build "linux-uclibc" "${target}" ;;
        *-android*)
            # https://github.com/rust-lang/rust/blob/1.80.0/src/ci/docker/host-x86_64/dist-android/Dockerfile#L9
            # NB: When updating this, the reminder to update tools/docker-manifest.sh and README.md.
            default_ndk_version="r25b"
            ndk_version="${NDK_VERSION:-"${default_ndk_version}"}"
            build "android" "${target}" "${ndk_version}" "${default_ndk_version}" \
                --build-arg "NDK_VERSION=${ndk_version}"
            ;;
        *-macos*) build "macos" "${target}" ;;
        *-ios*) build "ios" "${target}" ;;
        *-freebsd*)
            case "${target}" in
                riscv64*)
                    # riscv64 needs to build binutils from source.
                    # TODO: don't skip if actual host is arm64
                    case "${arch}" in
                        x86_64) ;;
                        *) continue ;;
                    esac
                    ;;
            esac
            if [[ -n "${FREEBSD_VERSION:-}" ]]; then
                freebsd_versions=("${FREEBSD_VERSION}")
            else
                # FreeBSD have binary compatibility with previous releases.
                # Therefore, the default is the minimum supported version.
                # However, we don't support old FreeBSD for the following targets:
                # - powerpc,powerpc64: FreeBSD 12 uses gcc instead of clang.
                # - powerpc64le,riscv64: available on FreeBSD 13+.
                # See also https://www.freebsd.org/releases/13.0R/announce.
                #
                # Supported releases: https://www.freebsd.org/security/#sup
                # FreeBSD 11 was EoL on 2021-09-30.
                # FreeBSD 12 was EoL on 2023-12-31.
                # https://www.freebsd.org/security/unsupported
                # https://endoflife.date/freebsd
                # NB: When updating this, the reminder to update tools/docker-manifest.sh and README.md.
                # TODO: 14.0 will be EoL on 2024-09-30.
                freebsd_versions=("13.3" "14.0")
            fi
            default_freebsd_version=13
            for freebsd_version in "${freebsd_versions[@]}"; do
                build "freebsd" "${target}" "${freebsd_version%%.*}" "${default_freebsd_version}" \
                    --build-arg "FREEBSD_VERSION=${freebsd_version}"
            done
            ;;
        *-netbsd*)
            if [[ -n "${NETBSD_VERSION:-}" ]]; then
                netbsd_versions=("${NETBSD_VERSION}")
            else
                # NetBSD have binary compatibility with previous releases.
                # Therefore, the default is the minimum supported version.
                # However, we cannot support old NetBSD for the following targets:
                # - aarch64: available on NetBSD 9+ https://www.netbsd.org/releases/formal-9/NetBSD-9.0.html
                # - aarch64_be: available on NetBSD 10+ https://www.netbsd.org/releases/formal-10/NetBSD-10.0.html
                #
                # Supported releases: https://www.netbsd.org/releases
                # NetBSD 7 was EoL on 2020-06-30.
                # NetBSD 8 was EoL on 2024-04-28.
                # https://www.netbsd.org/releases/formal.html
                # https://endoflife.date/netbsd
                # NB: When updating this, the reminder to update docker/base/build-docker.sh, tools/docker-manifest.sh, and README.md.
                netbsd_versions=("9" "10")
            fi
            default_netbsd_version=9
            for netbsd_version in "${netbsd_versions[@]}"; do
                case "${target}" in
                    aarch64_be-*)
                        default_netbsd_version=10
                        case "${netbsd_version}" in
                            9) continue ;;
                        esac
                        ;;
                esac
                build "netbsd" "${target}" "${netbsd_version%%.*}" "${default_netbsd_version}" \
                    --build-arg "NETBSD_VERSION=${netbsd_version}"
            done
            ;;
        *-openbsd*)
            case "${target}" in
                sparc64-*)
                    # sparc64 needs to build binutils from source.
                    # TODO: don't skip if actual host is arm64
                    case "${arch}" in
                        x86_64) ;;
                        *) continue ;;
                    esac
                    ;;
            esac
            if [[ -n "${OPENBSD_VERSION:-}" ]]; then
                openbsd_versions=("${OPENBSD_VERSION}")
            else
                # OpenBSD does not have binary compatibility with previous releases.
                # For now, we select the oldest supported version as default version.
                # https://github.com/rust-lang/libc/issues/570
                # https://github.com/golang/go/issues/15227
                # https://github.com/golang/go/wiki/OpenBSD
                # https://github.com/golang/go/wiki/MinimumRequirements#openbsd
                # The latest two releases are supported.
                # https://www.openbsd.org/faq/faq5.html#Flavors
                # https://en.wikipedia.org/wiki/OpenBSD#Releases
                # https://endoflife.date/openbsd
                # NB: When updating this, the reminder to update tools/docker-manifest.sh and README.md.
                openbsd_versions=("7.4" "7.5")
            fi
            default_openbsd_version="7.4"
            for openbsd_version in "${openbsd_versions[@]}"; do
                build "openbsd" "${target}" "${openbsd_version}" "${default_openbsd_version}" \
                    --build-arg "OPENBSD_VERSION=${openbsd_version}"
            done
            ;;
        *-dragonfly*)
            # https://mirror-master.dragonflybsd.org/iso-images
            # NB: When updating this, the reminder to update tools/docker-manifest.sh and README.md.
            dragonfly_version="${DRAGONFLY_VERSION:-"6.4.0"}"
            default_dragonfly_version="6"
            build "dragonfly" "${target}" "${dragonfly_version%%.*}" "${default_dragonfly_version}" \
                --build-arg "DRAGONFLY_VERSION=${dragonfly_version}"
            ;;
        *-solaris*) build "solaris" "${target}" ;;
        *-illumos*) build "illumos" "${target}" ;;
        *-redox*) build "redox" "${target}" ;;
        *-fuchsia*) build "fuchsia" "${target}" ;;
        *-wasi*) build "wasi" "${target}" ;;
        *-emscripten*) build "emscripten" "${target}" ;;
        *-windows-gnu*)
            case "${target}" in
                # i686-pc-windows-gnu needs to build gcc from source.
                i686-pc-windows-gnu)
                    case "${arch}" in
                        x86_64) ;;
                        *) continue ;;
                    esac
                    ;;
            esac
            case "${target}" in
                *-gnullvm*) build "windows-gnullvm" "${target}" ;;
                *) build "windows-gnu" "${target}" ;;
            esac
            ;;
        *-none*)
            case "${target}" in
                riscv*)
                    # Toolchains for these targets are not available on non-x86_64 host.
                    case "${arch}" in
                        x86_64) ;;
                        *) continue ;;
                    esac
                    ;;
            esac
            build "none" "${target}"
            ;;
        *) bail "unrecognized target '${target}'" ;;
    esac
done

x docker images "${repository}"
