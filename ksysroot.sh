#!/bin/sh
set -e

case "$(uname -s)" in
    Darwin)
        NATIVE_LINKER=ld64.lld
        ;;
    *)
        NATIVE_LINKER=ld.lld
        ;;
esac

: "${KSYSROOT_PREFIX:=$(dirname "$0")}"

. "${KSYSROOT_PREFIX}"/functions

if command -v brew >/dev/null; then
: "${LLVM_DIR:=$(brew --prefix llvm)/bin}"
: "${LLD_DIR:=$(brew --prefix lld)/bin}"
: "${PKG_CONFIG:=$(brew --prefix pkgconf)/bin/pkg-config}"
else
: "${LLVM_DIR:=$(dirname "$(realpath $(require_tool clang))")}"
: "${LLD_DIR:=$(dirname "$(require_tool lld)")}"
: "${PKG_CONFIG:=$(require_tool pkg-config)}"
fi

: "${DEBIAN_MIRROR:=http://ftp.nl.debian.org/debian/pool/main}"
: "${FREEBSD_MIRROR:=https://download.freebsd.org}"

: "${CACHE_DIR:=cache}"

. "${KSYSROOT_PREFIX}"/functions-native
. "${KSYSROOT_PREFIX}"/functions-debian
. "${KSYSROOT_PREFIX}"/functions-freebsd

ksysroot_test_meson() {
    : "${MESON:=$(require_tool meson)}"
    : "${MESON_SETUP_ARGS:=}"
    : "${MESON_COMPILE_ARGS:=}"

    local ksysroot_dir="$1"
    local base
    base="$(basename "$1")"

    local MESON_SETUP_ARGS="--native-file=${ksysroot_dir}/native.txt ${MESON_SETUP_ARGS}"
    if [ -e "${ksysroot_dir}/cross.txt" ]; then
        MESON_SETUP_ARGS="--cross-file=${ksysroot_dir}/cross.txt ${MESON_SETUP_ARGS}"
    fi

    local build_dir
    for i in c cxx; do
        build_dir="build-${base}-$i"
        rm -rf "${build_dir}"

        echo MESON_SETUP_ARGS="${MESON_SETUP_ARGS}"
        echo MESON_COMPILE_ARGS="${MESON_COMPILE_ARGS}"

        # shellcheck disable=SC2086
        ${MESON} setup ${MESON_SETUP_ARGS} "${build_dir}" "${KSYSROOT_PREFIX}/test-$i" && ${MESON} compile ${MESON_COMPILE_ARGS} -C "${build_dir}"
        test -x "${build_dir}"/main
        file "${build_dir}"/main
    done
}

ksysroot_test_pkgconf() {
    local ksysroot_dir="$1"
    local PKG_CONFIG
    local env="${ksysroot_dir}/bin/*-env"
    PKG_CONFIG="$(${env} sh -c "echo \${PKG_CONFIG}")"
    echo PKG_CONFIG="${PKG_CONFIG}"
    "${PKG_CONFIG}" --list-all
}

ksysroot_test_llvm() {
    local ksysroot_dir="$1"
    local env="${ksysroot_dir}/bin/*-env"

    for i in CC CXX CPP LD CC_FOR_BUILD CXX_FOR_BUILD CPP_FOR_BUILD LD_FOR_BUILD AR AS NM OBJCOPY OBJDUMP RANLIB READELF SIZE STRINGS STRIP; do
        local tool="$(${env} sh -c "echo \${$i}")"
        echo "$i" is "${tool}" 
        test -z "${CC}" || echo should not have leaked CC
        ${tool} --version
    done
}

ksysroot_test() {
    ksysroot_test_llvm "$@"
    ksysroot_test_pkgconf "$@"
    ksysroot_test_meson "$@"
}

test_all() {
    test_sysroot native

    # fix backports with Debian
    # armel-linux-gnu
    # mips64-linux-gnu
    # powerpc64-linux-gnu
    # riscv64-linux-gnu
    # mips64-linux-gnu

    # add from Alpine or OpenWRT
    # x86_64-linux-musl
    # arm-linux-musleabi 
    # arm-linux-musleabihf
    # for triple in aarch64-linux-gnu i686-linux-gnu x86_64-linux-gnu; do
    #     for version in 12 13; do
    #         test_sysroot ${triple}@debian${version}
    #     done
    # done

    for triple in aarch64-freebsd x86_64-freebsd i386-freebsd; do
    # for triple in x86_64-freebsd; do
        for version in 15.0-CURRENT 14.2-RELEASE 14.1-RELEASE 13.4-RELEASE 13.3-RELEASE; do
            test_sysroot ${triple}${version%.*}@freebsd${version}
        done
    done
}

usage() {
        echo Usage:
        echo     "$0" bom triple
        echo     "$0" frombom target-directory [bomfile]
        echo     "$0" install triple target-directory
        echo     "$0" test directory
        echo     "$0" test_meson directory
        echo     "$0" test_pkgconf directory
        echo     "$0" iterate
        echo     "$0" iterate1
        echo     "$0" iterate2
        echo     "$0" iterate3
}

dispatch() {
    local cmd="$1"
    shift
    case "${cmd}" in
        test|test_meson|test_pkgconf)
            ksysroot_"${cmd}" "$1"
            ;;
        frombom)
            ksysroot_frombom "$@"
            ;;
        iterate*)
            ksysroot_native_"${cmd}"
            ksysroot_debian_"${cmd}"
            ksysroot_freebsd_"${cmd}"
            ;;
        *)
            case "$1" in
                *linux*-gnu|*@debian*)
                    ksysroot_debian_"${cmd}" "$@"
                    ;;
                *freebsd*)
                    ksysroot_freebsd_"${cmd}" "$@"
                    ;;
                native)
                    ksysroot_native_"${cmd}" "$@"
                    ;;
                *)
                    usage
                    return 1                
            esac
            1>&2 echo Performed "${cmd}" "$@" for "${KSYSROOT_TRIPLE}" in "${KSYSROOT_PREFIX}"
            ;;
    esac
}

dispatch "$@"