#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0 OR MIT
set -eEuo pipefail
IFS=$'\n\t'
cd "$(dirname "$0")"/..

# shellcheck disable=SC2154
trap 's=$?; echo >&2 "$0: error on line "${LINENO}": ${BASH_COMMAND}"; exit ${s}' ERR

# USAGE:
#   ./tools/docker-manifest.sh [TARGET]...

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
retry() {
    for i in {1..10}; do
        if "$@"; then
            return 0
        else
            sleep "${i}"
        fi
    done
    "$@"
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
        tag+="${sys_version}"
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
            (
                set -x
                retry docker manifest push --purge "${tag}"
            )
        done
    fi
}

for target in "${targets[@]}"; do
    arches=(amd64)
    # NB: When updating this, the reminder to update tools/build-docker.sh.
    case "${target}" in
        *-linux-gnu*)
            arches=(amd64 arm64v8)
            case "${target}" in
                aarch64_be-* | armeb-* | arm-*hf | csky-* | loongarch64-* | riscv32* | powerpc64-* | powerpc-*spe)
                    # aarch64_be-*|armeb-*|arm-*hf|csky-*|loongarch64-*|riscv32*: Toolchains for these targets are not available on non-x86_64 host.
                    # powerpc64-*|powerpc-*spe: gcc-(powerpc64-linux-gnu|powerpc-linux-gnuspe) for arm64 host is not available on 24.04.
                    arches=(amd64)
                    ;;
            esac
            docker_manifest "${target}"
            ;;
        *-linux-musl*)
            if [[ -n "${MUSL_VERSION:-}" ]]; then
                musl_versions=("${MUSL_VERSION}")
            else
                # NB: When updating this, the reminder to update tools/build-docker.sh.
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
                docker_manifest "${target}" "${musl_version}" "${default_musl_version}"
            done
            ;;
        *-linux-uclibc*) docker_manifest "${target}" ;;
        *-android*)
            # NB: When updating this, the reminder to update tools/build-docker.sh.
            default_ndk_version="r25b"
            ndk_version="${NDK_VERSION:-"${default_ndk_version}"}"
            docker_manifest "${target}" "${ndk_version}" "${default_ndk_version}"
            ;;
        *-macos*) docker_manifest "${target}" ;;
        *-ios*) docker_manifest "${target}" ;;
        *-freebsd*)
            case "${target}" in
                riscv64*)
                    # riscv64 needs to build binutils from source.
                    arches=(amd64)
                    ;;
            esac
            if [[ -n "${FREEBSD_VERSION:-}" ]]; then
                freebsd_versions=("${FREEBSD_VERSION}")
            else
                # NB: When updating this, the reminder to update tools/build-docker.sh.
                freebsd_versions=("13.4" "14.1")
            fi
            default_freebsd_version=13
            for freebsd_version in "${freebsd_versions[@]}"; do
                docker_manifest "${target}" "${freebsd_version%%.*}" "${default_freebsd_version}"
            done
            ;;
        *-netbsd*)
            if [[ -n "${NETBSD_VERSION:-}" ]]; then
                netbsd_versions=("${NETBSD_VERSION}")
            else
                # NB: When updating this, the reminder to update tools/build-docker.sh.
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
            if [[ -n "${OPENBSD_VERSION:-}" ]]; then
                openbsd_versions=("${OPENBSD_VERSION}")
            else
                # NB: When updating this, the reminder to update tools/build-docker.sh.
                openbsd_versions=("7.5" "7.6")
            fi
            default_openbsd_version="7.5"
            for openbsd_version in "${openbsd_versions[@]}"; do
                docker_manifest "${target}" "${openbsd_version}" "${default_openbsd_version}"
            done
            ;;
        *-dragonfly*)
            # NB: When updating this, the reminder to update tools/build-docker.sh.
            dragonfly_version="${DRAGONFLY_VERSION:-"6.4.0"}"
            default_dragonfly_version="6"
            docker_manifest "${target}" "${dragonfly_version%%.*}" "${default_dragonfly_version}"
            ;;
        *-solaris*) docker_manifest "${target}" ;;
        *-illumos*) docker_manifest "${target}" ;;
        *-redox*) docker_manifest "${target}" ;;
        *-fuchsia*) docker_manifest "${target}" ;;
        *-wasi*)
            arches=(amd64 arm64v8)
            docker_manifest "${target}"
            ;;
        *-emscripten*)
            arches=(amd64 arm64v8)
            docker_manifest "${target}"
            ;;
        *-windows-gnu*)
            arches=(amd64 arm64v8)
            case "${target}" in
                # i686-pc-windows-gnu needs to build gcc from source.
                i686-pc-windows-gnu) arches=(amd64) ;;
            esac
            docker_manifest "${target}"
            ;;
        *-none*)
            arches=(amd64 arm64v8)
            case "${target}" in
                # Toolchains for these targets are not available on non-x86_64 host.
                riscv*) arches=(amd64) ;;
            esac
            docker_manifest "${target}"
            ;;
        *) echo >&2 "error: unrecognized target '${target}'" && exit 1 ;;
    esac
done
