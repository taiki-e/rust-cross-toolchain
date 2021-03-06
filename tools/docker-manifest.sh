#!/bin/bash
set -euo pipefail
IFS=$'\n\t'
cd "$(dirname "$0")"/..

# USAGE:
#   ./tools/docker-manifest.sh [TARGET]...

x() {
    local cmd="$1"
    shift
    if [[ -n "${dry_run:-}" ]]; then
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

if [[ "${1:-}" == "-"* ]]; then
    cat <<EOF
USAGE:
    $0 [TARGET]...
EOF
    exit 1
fi
# shellcheck disable=SC1091
. tools/target-list-shared.sh
if [[ $# -gt 0 ]]; then
    targets=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) dry_run=1 ;;
            -*) echo >&2 "error: unknown argument '$1'" && exit 1 ;;
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

github_tag="dev"
is_release=""
if [[ "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
    github_tag="${GITHUB_REF_NAME}"
    is_release=1
fi

docker_manifest() {
    local target="$1"
    shift

    local tag="${repository}:${target}"
    local tags=()
    if [[ "${1:-}" =~ ^[0-9]+.* ]]; then
        local sys_version="$1"
        local default_sys_version="$2"
        shift
        shift
        if [[ "${sys_version}" == "${default_sys_version}" ]]; then
            if [[ -n "${is_release}" ]]; then
                tags+=("${tag}")
            fi
            tags+=("${tag}-${github_tag}")
        fi
        local tag="${tag}${sys_version}"
    fi
    if [[ -n "${is_release}" ]]; then
        tags+=("${tag}")
    fi
    tags+=("${tag}-${github_tag}")
    for tag in "${tags[@]}"; do
        local args=()
        for arch in "${arches[@]}"; do
            args+=("${tag}-${arch}")
        done
        x docker manifest create --amend "${tag}" "${args[@]}"
        for arch in "${arches[@]}"; do
            case "${arch}" in
                amd64)
                    x docker manifest annotate --os linux --arch amd64 "${tag}" "${tag}-${arch}"
                    ;;
                arm64v8)
                    x docker manifest annotate --os linux --arch arm64 --variant v8 "${tag}" "${tag}-${arch}"
                    ;;
                *) echo >&2 "error: unsupported architecture '${arch}'" && exit 1 ;;
            esac
        done
    done
    if [[ -n "${PUSH_TO_GHCR:-}" ]]; then
        for tag in "${tags[@]}"; do
            x docker manifest push --purge "${tag}"
        done
    fi
}

for target in "${targets[@]}"; do
    arches=(amd64)
    # When updating this, the reminder to update tools/build-docker.sh.
    case "${target}" in
        *-linux-gnu*)
            arches=(amd64 arm64v8)
            case "${target}" in
                aarch64_be-* | arm-*hf | riscv32gc-* | powerpc-* | powerpc64-* | sparc-* | sparc64-*)
                    # aarch64_be-*|arm-*hf|riscv32gc-*: Toolchains for these targets are not available on non-x86_64 host.
                    # powerpc-*|powerpc64-*|sparc-*|sparc64-*: gcc-(powerpc|powerpc64|sparc64)-linux-gnu(spe) for arm64 host is not available in ubuntu 20.04.
                    arches=(amd64)
                    ;;
                mips*)
                    # gcc-(mips|mipsel|mips64|mips64el|mipsisa32r6|mipsisa32r6el)-linux-gnu for arm64 host is not available in ubuntu 20.04.
                    # TODO: consider using debian bullseye that has the same glibc version as ubuntu 20.04.
                    arches=(amd64)
                    ;;
            esac
            docker_manifest "${target}"
            ;;
        *-linux-musl*)
            if [[ -n "${MUSL_VERSION:-}" ]]; then
                musl_versions=("${MUSL_VERSION}")
            else
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
                        docker_manifest "${target}" "${musl_version}" "${default_musl_version}"
                        ;;
                    *)
                        docker_manifest "${target}" "${musl_version}" "${default_musl_version}"
                        ;;
                esac
            done
            ;;
        *-linux-uclibc*) docker_manifest "${target}" ;;
        *-android*)
            # https://github.com/rust-lang/rust/blob/27143a9094b55a00d5f440b05b0cb4233b300d33/src/ci/docker/host-x86_64/dist-android/Dockerfile#L10-L15
            case "${target}" in
                aarch64-* | x86_64-*)
                    default_ndk_version=21
                    ndk_versions=("21")
                    ;;
                arm* | thumb* | i686-*)
                    default_ndk_version=14
                    ndk_versions=("14" "21")
                    ;;
                *) echo >&2 "unrecognized target '${RUST_TARGET}'" && exit 1 ;;
            esac
            if [[ -n "${NDK_VERSION:-}" ]]; then
                ndk_versions=("${NDK_VERSION}")
            fi
            for ndk_version in "${ndk_versions[@]}"; do
                docker_manifest "${target}" "${ndk_version}" "${default_ndk_version}"
            done
            ;;
        *-macos*) docker_manifest "${target}" ;;
        *-ios*) docker_manifest "${target}" ;;
        *-freebsd*)
            case "${target}" in
                riscv64gc-*)
                    # riscv64gc needs to build binutils from source.
                    arches=(amd64)
                    ;;
            esac
            if [[ -n "${FREEBSD_VERSION:-}" ]]; then
                freebsd_versions=("${FREEBSD_VERSION}")
            else
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
                docker_manifest "${target}" "${freebsd_version%%.*}" "${default_freebsd_version}"
            done
            ;;
        *-netbsd*)
            if [[ -n "${NETBSD_VERSION:-}" ]]; then
                netbsd_versions=("${NETBSD_VERSION}")
            else
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
                docker_manifest "${target}" "${netbsd_version%%.*}" "${default_netbsd_version}"
            done
            ;;
        *-openbsd*)
            case "${target}" in
                sparc64-*)
                    # sparc64 needs to build binutils from source.
                    arches=(amd64)
                    ;;
            esac
            openbsd_version="${OPENBSD_VERSION:-"7.0"}"
            default_openbsd_version="7.0"
            docker_manifest "${target}" "${openbsd_version}" "${default_openbsd_version}"
            ;;
        *-dragonfly*)
            # https://mirror-master.dragonflybsd.org/iso-images
            dragonfly_version="${DRAGONFLY_VERSION:-"6.0.1"}"
            default_dragonfly_version=6
            docker_manifest "${target}" "${dragonfly_version%%.*}" "${default_dragonfly_version}"
            ;;
        *-solaris*) docker_manifest "${target}" ;;
        *-illumos*) docker_manifest "${target}" ;;
        *-redox*) docker_manifest "${target}" ;;
        *-fuchsia*) docker_manifest "${target}" ;;
        *-wasi*) docker_manifest "${target}" ;;
        *-emscripten*) docker_manifest "${target}" ;;
        *-windows-gnu*)
            arches=(amd64 arm64v8)
            case "${target}" in
                i686-*)
                    # i686 needs to build gcc from source.
                    arches=(amd64)
                    ;;
            esac
            docker_manifest "${target}"
            ;;
        *-none*)
            arches=(amd64 arm64v8)
            case "${target}" in
                riscv*)
                    # Toolchains for these targets are not available on non-x86_64 host.
                    arches=(amd64)
                    ;;
            esac
            docker_manifest "${target}"
            ;;
        *) echo >&2 "error: unrecognized target '${target}'" && exit 1 ;;
    esac
done
