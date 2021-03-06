#!/bin/sh
#
# this script is used to rebuild the Android emulator from sources
# in the current directory. It also contains logic to speed up the
# rebuild if it detects that you're using the Android build system
#
# here's the list of environment variables you can define before
# calling this script to control it (besides options):
#
#

# first, let's see which system we're running this on
cd `dirname $0`

PROGNAME=`basename $0`
PROGDIR=`dirname $0`

## Logging support
##
VERBOSE=yes
VERBOSE2=no

panic () {
    echo "ERROR: $@"
    exit 1
}

log () {
    if [ "$VERBOSE" = "yes" ] ; then
        echo "$1"
    fi
}

log2 () {
    if [ "$VERBOSE2" = "yes" ] ; then
        echo "$1"
    fi
}

## Normalize OS and CPU
##

BUILD_ARCH=$(uname -m)
case "$BUILD_ARCH" in
    i?86) BUILD_ARCH=x86
    ;;
    x86_64|amd64) BUILD_ARCH=x86_64
    ;;
    *) panic "$BUILD_ARCH builds are not supported!"
    ;;
esac

log2 "BUILD_ARCH=$BUILD_ARCH"

# at this point, the supported values for CPU are:
#   x86
#   x86_64
#
# other values may be possible but haven't been tested
#

BUILD_EXEEXT=
BUILD_OS=`uname -s`
case "$BUILD_OS" in
    Darwin) BUILD_OS=darwin;;
    Linux) BUILD_OS=linux;;
    FreeBSD) BUILD_OS=freebsd;;
    CYGWIN*|*_NT-*)
        panic "Please build Windows binaries on Linux with --mingw option."
        ;;
    *) panic "Unknown build OS: $BUILD_OS";;
esac

BUILD_TAG=$BUILD_OS-$BUILD_ARCH

log2 "BUILD_TAG=$BUILD_TAG"
log2 "BUILD_EXEEXT=$BUILD_EXEEXT"

HOST_OS=$BUILD_OS
HOST_ARCH=$BUILD_ARCH
HOST_TAG=$HOST_OS-$HOST_ARCH


#### Toolchain support
####

WINDRES=

# Various probes are going to need to run a small C program
TMPC=/tmp/android-$$-test.c
TMPO=/tmp/android-$$-test.o
TMPE=/tmp/android-$$-test$BUILD_EXEEXT
TMPL=/tmp/android-$$-test.log

# cleanup temporary files
clean_temp () {
    rm -f $TMPC $TMPO $TMPL $TMPLE
}

# cleanup temp files then exit with an error
clean_exit () {
    clean_temp
    exit 1
}

# this function will setup the compiler and linker and check that they work as advertized
setup_toolchain () {
    if [ -z "$CC" ] ; then
        CC=gcc
    fi

    # check that we can compile a trivial C program with this compiler
    cat > $TMPC <<EOF
int main(void) {}
EOF
    compile
    if [ $? != 0 ] ; then
        echo "your C compiler doesn't seem to work: $CC"
        cat $TMPL
        clean_exit
    fi
    log "CC         : compiler check ok ($CC)"
    CC_VER=`$CC --version`
    log "CC_VER     : $CC_VER"

    # check that we can link the trivial program into an executable
    if [ -z "$LD" ] ; then
        LD=$CC
    fi
    link
    if [ $? != 0 ] ; then
        echo "your linker doesn't seem to work:"
        cat $TMPL
        clean_exit
    fi
    log "LD         : linker check ok ($LD)"

    if [ -z "$AR" ]; then
        AR=ar
    fi
    log "AR         : archiver ($AR)"
    clean_temp
}

# try to compile the current source file in $TMPC into an object
# stores the error log into $TMPL
#
compile () {
    log2 "Object     : $CC -o $TMPO -c $CFLAGS $TMPC"
    $CC -o $TMPO -c $CFLAGS $TMPC 2> $TMPL
}

# try to link the recently built file into an executable. error log in $TMPL
#
link() {
    log2 "Link      : $LD -o $TMPE $TMPO $LDFLAGS"
    $LD -o $TMPE $TMPO $LDFLAGS 2> $TMPL
}

## Feature test support
##

# check that a given C header file exists on the host system
# $1: variable name which will be set to "yes" or "no" depending on result
# $2: header name
#
# you can define EXTRA_CFLAGS for extra C compiler flags
# for convenience, this variable will be unset by the function.
#
feature_check_header () {
    local result_ch OLD_CFLAGS
    log2 "HeaderCheck: $2"
    echo "#include $2" > $TMPC
    cat >> $TMPC <<EOF
        int main(void) { return 0; }
EOF
    OLD_CFLAGS=$CFLAGS
    CFLAGS="$CFLAGS $EXTRA_CFLAGS"
    compile
    if [ $? != 0 ]; then
        result_ch=no
    else
        result_ch=yes
    fi
    log "HeaderCheck: $2 [$result_ch]"
    EXTRA_CFLAGS=
    CFLAGS=$OLD_CFLAGS
    eval $1=$result_ch
    clean_temp
}

# Find pattern $1 in string $2
# This is to be used in if statements as in:
#
#    if pattern_match <pattern> <string>; then
#       ...
#    fi
#
pattern_match () {
    echo "$2" | grep -q -E -e "$1"
}

# Find if a given shell program is available.
# We need to take care of the fact that the 'which <foo>' command
# may return either an empty string (Linux) or something like
# "no <foo> in ..." (Darwin). Also, we need to redirect stderr
# to /dev/null for Cygwin
#
# $1: variable name
# $2: program name
#
# Result: set $1 to the full path of the corresponding command
#         or to the empty/undefined string if not available
#
find_program () {
    local PROG
    PROG=`which $2 2>/dev/null || true`
    if [ -n "$PROG" ] ; then
        if pattern_match '^no ' "$PROG"; then
            PROG=
        fi
    fi
    eval $1="$PROG"
}

# Default value of --ui option.
UI_DEFAULT=qt

# Default value of --gles option.
GLES_DEFAULT=dgl

# Parse options
OPTION_DEBUG=no
OPTION_IGNORE_AUDIO=no
OPTION_AOSP_PREBUILTS_DIR=
OPTION_OUT_DIR=
OPTION_HELP=no
OPTION_STRIP=yes
OPTION_MINGW=no
OPTION_UI=
OPTION_GLES=
OPTION_SDK_REV=
OPTION_SYMBOLS=no

GLES_SUPPORT=no

PCBIOS_PROBE=yes

HOST_CC=${CC:-gcc}
OPTION_CC=

HOST_CXX=${CXX:-g++}
OPTION_CXX=

AOSP_PREBUILTS_DIR=$(dirname "$0")/../../prebuilts
if [ -d "$AOSP_PREBUILTS_DIR" ]; then
    AOSP_PREBUILTS_DIR=$(cd "$AOSP_PREBUILTS_DIR" && pwd -P 2>/dev/null)
else
    AOSP_PREBUILTS_DIR=
fi

for opt do
  optarg=`expr "x$opt" : 'x[^=]*=\(.*\)'`
  case "$opt" in
  --help|-h|-\?) OPTION_HELP=yes
  ;;
  --verbose)
    if [ "$VERBOSE" = "yes" ] ; then
        VERBOSE2=yes
    else
        VERBOSE=yes
    fi
  ;;
  --verbosity=*)
    if [ "$optarg" -gt 1 ]; then
        VERBOSE=yes
        if [ "$optarg" -gt 2 ]; then
            VERBOSE2=yes
        fi
    fi
    ;;

  --debug) OPTION_DEBUG=yes; OPTION_STRIP=no
  ;;
  --mingw) OPTION_MINGW=yes
  ;;
  --cc=*) OPTION_CC="$optarg"
  ;;
  --cxx=*) OPTION_CXX="$optarg"
  ;;
  --strip) OPTION_STRIP=yes
  ;;
  --no-strip) OPTION_STRIP=no
  ;;
  --out-dir=*) OPTION_OUT_DIR=$optarg
  ;;
  --aosp-prebuilts-dir=*) OPTION_AOSP_PREBUILTS_DIR=$optarg
  ;;
  --build-qemu-android) true # Ignored, used by android-rebuild.sh only.
  ;;
  --no-pcbios) PCBIOS_PROBE=no
  ;;
  --no-tests)
  # Ignore this option, only used by android-rebuild.sh
  ;;
  --symbols) OPTION_SYMBOLS=yes
  ;;
  --no-symbols) OPTION_SYMBOLS=no
  ;;
  --ui=sdl2) OPTION_UI=sdl2
  ;;
  --ui=qt) OPTION_UI=qt
  ;;
  --gles=dgl) OPTION_GLES=dgl
  ;;
  --gles=angle) OPTION_GLES=angle
  ;;
  --ui=*) echo "Unknown --ui value, try one of: sdl2 qt"
  ;;
  --gles=*) echo "Unknown --gles value, try one of: dgl angle"
  ;;
  --sdk-revision=*) ANDROID_SDK_TOOLS_REVISION=$optarg
  ;;
  *)
    echo "unknown option '$opt', use --help"
    exit 1
  esac
done

# Print the help message
#
if [ "$OPTION_HELP" = "yes" ] ; then
    cat << EOF

Usage: rebuild.sh [options]
Options: [defaults in brackets after descriptions]
EOF
    echo "Standard options:"
    echo "  --help                      Print this message"
    echo "  --cc=PATH                   Specify C compiler [$HOST_CC]"
    echo "  --cxx=PATH                  Specify C++ compiler [$HOST_CXX]"
    echo "  --no-strip                  Do not strip emulator executables."
    echo "  --strip                     Strip emulator executables (default)."
    echo "  --symbols                   Generating Breakpad symbol files."
    echo "  --no-symbols                Do not generate Breakpad symbol files (default)."
    echo "  --debug                     Enable debug (-O0 -g) build"
    echo "  --ui=sdl2                   Use SDL2-based UI backend."
    echo "  --ui=qt                     Use Qt-based UI backend (default)."
    echo "  --gles=dgl                  Build the OpenGLES to Desktop OpenGL Translator (default)"
    echo "  --gles=angle                Build the OpenGLES to ANGLE wrapper"
    echo "  --aosp-prebuilts-dir=<path> Use specific prebuilt toolchain root directory [$AOSP_PREBUILTS_DIR]"
    echo "  --out-dir=<path>            Use specific output directory [objs/]"
    echo "  --mingw                     Build Windows executable on Linux"
    echo "  --verbose                   Verbose configuration"
    echo "  --debug                     Build debug version of the emulator"
    echo "  --no-pcbios                 Disable copying of PC Bios files"
    echo "  --no-tests                  Don't run unit test suite"
    if [ "$IN_ANDROID_REBUILD_SH" ]; then
        echo "  --build-qemu-android        Also build qemu-android binaries"
    fi
    echo ""
    exit 1
fi

if [ "$OPTION_AOSP_PREBUILTS_DIR" ]; then
    if [ ! -d "$OPTION_AOSP_PREBUILTS_DIR"/gcc -a \
         ! -d "$OPTION_AOSP_PREBUILTS_DIR"/clang ]; then
        echo "ERROR: Prebuilts directory does not exist: $OPTION_AOSP_PREBUILTS_DIR/gcc"
        exit 1
    fi
    AOSP_PREBUILTS_DIR=$OPTION_AOSP_PREBUILTS_DIR
fi

if [ -z "$OPTION_UI" ]; then
    OPTION_UI=$UI_DEFAULT
    log "Auto-config: --ui=$OPTION_UI"
fi

if [ -z "$OPTION_GLES" ]; then
    OPTION_GLES=$GLES_DEFAULT
    log "Auto-config: --gles=$OPTION_GLES"
fi

if [ "$OPTION_OUT_DIR" ]; then
    OUT_DIR="$OPTION_OUT_DIR"
    mkdir -p "$OUT_DIR" || panic "Could not create output directory: $OUT_DIR"
else
    OUT_DIR=objs
    log "Auto-config: --out-dir=objs"
fi

CCACHE=
if [ "$USE_CCACHE" != 0 ]; then
    CCACHE=$(which ccache 2>/dev/null || true)
fi

if [ -n "$CCACHE" -a -f "$CCACHE" ]; then
    if [ "$HOST_OS" == "darwin" -a "$OPTION_DEBUG" == "yes" ]; then
        # http://llvm.org/bugs/show_bug.cgi?id=20297
        # ccache works for mingw/gdb, therefore probably works for gcc/gdb
        log "Prebuilt   : CCACHE disabled for OSX debug builds"
        CCACHE=
    else
        log "Prebuilt   : CCACHE=$CCACHE"
    fi
else
    log "Prebuilt   : CCACHE can't be found"
    CCACHE=
fi

# Use gen-android-sdk-toolchain.sh to generate a toolchain that will
# build binaries compatible with the SDK deployement systems.
GEN_SDK=$PROGDIR/android/scripts/gen-android-sdk-toolchain.sh
GEN_SDK_FLAGS=--cxx11
if [ "$CCACHE" ]; then
    GEN_SDK_FLAGS="$GEN_SDK_FLAGS --ccache=$CCACHE"
else
    GEN_SDK_FLAGS="$GEN_SDK_FLAGS --no-ccache"
fi
SDK_TOOLCHAIN_DIR=$OUT_DIR/build/toolchain
GEN_SDK_FLAGS="$GEN_SDK_FLAGS --aosp-dir=$AOSP_PREBUILTS_DIR/.."
"$GEN_SDK" $GEN_SDK_FLAGS "$SDK_TOOLCHAIN_DIR" || panic "Cannot generate SDK toolchain!"
BINPREFIX=$("$GEN_SDK" $GEN_SDK_FLAGS --print=binprefix "$SDK_TOOLCHAIN_DIR")
CC="$SDK_TOOLCHAIN_DIR/${BINPREFIX}gcc"
CXX="$SDK_TOOLCHAIN_DIR/${BINPREFIX}g++"
AR="$SDK_TOOLCHAIN_DIR/${BINPREFIX}ar"
LD=$CC
OBJCOPY="$SDK_TOOLCHAIN_DIR/${BINPREFIX}objcopy"

if [ -n "$OPTION_CC" ]; then
    echo "Using specified C compiler: $OPTION_CC"
    CC="$OPTION_CC"
fi

if [ -n "$OPTION_CXX" ]; then
    echo "Using specified C++ compiler: $OPTION_CXX"
    CC="$OPTION_CXX"
fi

setup_toolchain

BUILD_AR=$AR
BUILD_CC=$CC
BUILD_CXX=$CXX
BUILD_LD=$LD
BUILD_OBJCOPY=$OBJCOPY
BUILD_CFLAGS=$CFLAGS
BUILD_CXXFLAGS=$CXXFLAGS
BUILD_LDFLAGS=$LDFLAGS

if [ "$OPTION_MINGW" = "yes" ] ; then
    # Are we on Linux ?
    log "Mingw      : Checking for Linux host"
    if [ "$HOST_OS" != "linux" ] ; then
        echo "Sorry, but mingw compilation is only supported on Linux !"
        exit 1
    fi
    GEN_SDK_FLAGS="$GEN_SDK_FLAGS --host=windows-x86_64"
    "$GEN_SDK" $GEN_SDK_FLAGS "$SDK_TOOLCHAIN_DIR" || panic "Cannot generate SDK toolchain!"
    BINPREFIX=$("$GEN_SDK" $GEN_SDK_FLAGS --print=binprefix "$SDK_TOOLCHAIN_DIR")
    CC="$SDK_TOOLCHAIN_DIR/${BINPREFIX}gcc"
    CXX="$SDK_TOOLCHAIN_DIR/${BINPREFIX}g++"
    LD=$CC
    WINDRES=$SDK_TOOLCHAIN_DIR/${BINPREFIX}windres
    AR="$SDK_TOOLCHAIN_DIR/${BINPREFIX}ar"
    OBJCOPY="$SDK_TOOLCHAIN_DIR/${BINPREFIX}objcopy"
    HOST_OS=windows
    HOST_TAG=$HOST_OS-$HOST_ARCH
fi

# Try to find the GLES emulation headers and libraries automatically
GLES_DIR=distrib/android-emugl
if [ ! -d "$GLES_DIR" ]; then
    panic "GLES       : Could not find GPU emulation sources!: $GLES_DIR"
else
    echo "GLES       : Found GPU emulation sources: $GLES_DIR"
fi

if [ "$PCBIOS_PROBE" = "yes" ]; then
    PCBIOS_DIR=$AOSP_PREBUILTS_DIR/qemu-kernel/x86/pc-bios
    if [ ! -d "$PCBIOS_DIR" ]; then
        log2 "PC Bios    : Probing $PCBIOS_DIR (missing)"
        PCBIOS_DIR=../pc-bios
    fi
    log2 "PC Bios    : Probing $PCBIOS_DIR"
    if [ ! -d "$PCBIOS_DIR" ]; then
        log "PC Bios    : Could not find prebuilts directory."
    else
        mkdir -p $OUT_DIR/lib/pc-bios
        for BIOS_FILE in bios.bin vgabios-cirrus.bin bios-256k.bin efi-virtio.rom kvmvapic.bin linuxboot.bin; do
            log "PC Bios    : Copying $BIOS_FILE"
            cp -f $PCBIOS_DIR/$BIOS_FILE $OUT_DIR/lib/pc-bios/$BIOS_FILE
        done
    fi
fi

setup_toolchain

###
###  Audio subsystems probes
###
PROBE_COREAUDIO=no
PROBE_ALSA=no
PROBE_OSS=no
PROBE_ESD=no
PROBE_PULSEAUDIO=no
PROBE_WINAUDIO=no

case "$HOST_OS" in
    darwin) PROBE_COREAUDIO=yes;
    ;;
    linux) PROBE_ALSA=yes; PROBE_OSS=yes; PROBE_ESD=yes; PROBE_PULSEAUDIO=yes;
    ;;
    freebsd) PROBE_OSS=yes;
    ;;
    windows) PROBE_WINAUDIO=yes
    ;;
esac

###
###  Zlib probe
###
ZLIB_PREBUILTS_DIR=$AOSP_PREBUILTS_DIR/android-emulator-build/qemu-android-deps
if [ -d "$ZLIB_PREBUILTS_DIR" ]; then
    log "Zlib prebuilts dir :$ZLIB_PREBUILTS_DIR"
else
    panic "Missing prebuilts directory: $ZLIB_PREBUILTS_DIR"
fi

###
###  Libpng probe
###
LIBPNG_PREBUILTS_DIR=$AOSP_PREBUILTS_DIR/android-emulator-build/qemu-android-deps
if [ -d "$LIBPNG_PREBUILTS_DIR" ]; then
    log "Libpng prebuilts dir :$LIBPNG_PREBUILTS_DIR"
else
    panic "Missing prebuilts directory: $LIBPNG_PREBUILTS_DIR"
fi

###
###  LibSDL2 probe
###
SDL2_PREBUILTS_DIR=
if [ "$OPTION_UI" = "sdl2" ]; then
    SDL2_PREBUILTS_DIR=$AOSP_PREBUILTS_DIR/android-emulator-build/qemu-android-deps
    if [ -d "$SDL2_PREBUILTS_DIR" ]; then
        log "LibSDL2 prebuilts dir: $SDL2_PREBUILTS_DIR"
    else
        panic "Missing libSDL2 prebuilts directory: $SDL2_PREBUILTS_DIR"
    fi
fi

###
###  Libxml2 probe
###
LIBXML2_PREBUILTS_DIR=$AOSP_PREBUILTS_DIR/android-emulator-build/common/libxml2
if [ -d "$LIBXML2_PREBUILTS_DIR" ]; then
    log "Libxml2 prebuilts dir: $LIBXML2_PREBUILTS_DIR"
else
    panic "Missing prebuilts directory (please run build-libxml2.sh): $LIBXML2_PREBUILTS_DIR"
fi

###
###  Libcurl probe
###
LIBCURL_PREBUILTS_DIR=$AOSP_PREBUILTS_DIR/android-emulator-build/curl
if [ -d "$LIBCURL_PREBUILTS_DIR" ]; then
    log "LibCURL prebuilts dir: $LIBCURL_PREBUILTS_DIR"
else
    panic "Missing prebuilts directory (please run build-curl.sh): $LIBCURL_PREBUILTS_DIR"
fi

CACERTS_FILE="$PROGDIR/android/data/ca-bundle.pem"
if [ ! -f "$CACERTS_FILE" ]; then
    panic "Missing cacerts file: $CACERTS_FILE"
fi
mkdir -p $OUT_DIR/lib
cp -f "$CACERTS_FILE" "$OUT_DIR/lib/"

###
###  Breakpad probe
###
BREAKPAD_PREBUILTS_DIR=$AOSP_PREBUILTS_DIR/android-emulator-build/common/breakpad
if [ -d "$BREAKPAD_PREBUILTS_DIR" ]; then
    log "BREAKPAD prebuilts dir: $BREAKPAD_PREBUILTS_DIR"
    if [ "$OPTION_MINGW" = "yes" ] ; then
        DUMPSYMS=$BREAKPAD_PREBUILTS_DIR/$BUILD_TAG/bin/dump_syms_dwarf
    else
        ##Mac and Linux builds
        DUMPSYMS=$BREAKPAD_PREBUILTS_DIR/$BUILD_TAG/bin/dump_syms
    fi
else
    panic "Missing prebuilts directory (please run build-breakpad.sh): $BREAKPAD_PREBUILTS_DIR"
fi

###
###  Qt probe
###
QT_PREBUILTS_DIR=
if [ "$OPTION_UI" = "qt" ]; then
    QT_PREBUILTS_DIR=$AOSP_PREBUILTS_DIR/android-emulator-build/qt
    if [ -d "$QT_PREBUILTS_DIR" ]; then
        log "Qt prebuilts dir: $QT_PREBUILTS_DIR"
    else
        panic "Missing Qt prebuilts directory (please run build-qt.sh): $QT_PREBUILTS_DIR"
    fi
fi

###
###  e2fsprogs probe
###
E2FSPROGS_PREBUILTS_DIR=
if true; then
    E2FSPROGS_PREBUILTS_DIR=$AOSP_PREBUILTS_DIR/android-emulator-build/common/e2fsprogs
    if [ -d "$E2FSPROGS_PREBUILTS_DIR" ]; then
        log "e2fsprogs prebuilts dir: $E2FSPROGS_PREBUILTS_DIR"
    else
        echo "WARNING: Missing e2fsprogs prebuilts directory: $E2FSPROGS_PREBUILTS_DIR"
    fi
fi

# create the objs directory that is going to contain all generated files
# including the configuration ones
#
mkdir -p $OUT_DIR

###
###  Compiler probe
###

####
####  Host system probe
####

# because the previous version could be read-only
clean_temp

# check whether we have <byteswap.h>
#
feature_check_header HAVE_BYTESWAP_H      "<byteswap.h>"
feature_check_header HAVE_MACHINE_BSWAP_H "<machine/bswap.h>"
feature_check_header HAVE_FNMATCH_H       "<fnmatch.h>"

# check for Mingw version.
MINGW_VERSION=
if [ "$HOST_OS" = "windows" ]; then
log "Mingw      : Probing for GCC version."
GCC_VERSION=$($CC -v 2>&1 | awk '$1 == "gcc" && $2 == "version" { print $3; }')
GCC_MAJOR=$(echo "$GCC_VERSION" | cut -f1 -d.)
GCC_MINOR=$(echo "$GCC_VERSION" | cut -f2 -d.)
log "Mingw      : Found GCC version $GCC_MAJOR.$GCC_MINOR [$GCC_VERSION]"
MINGW_GCC_VERSION=$(( $GCC_MAJOR * 100 + $GCC_MINOR ))
fi
# Build the config.make file
#

case $BUILD_OS in
    windows)
        BUILD_EXEEXT=.exe
        BUILD_DLLEXT=.dll
        ;;
    darwin)
        BUILD_EXEEXT=
        BUILD_DLLEXT=.dylib
        ;;
    *)
        BUILD_EXEEXT=
        BUILD_DLLEXT=
        ;;
esac

case $HOST_OS in
    windows)
        HOST_EXEEXT=.exe
        HOST_DLLEXT=.dll
        ;;
    darwin)
        HOST_EXEXT=
        HOST_DLLEXT=.dylib
        ;;
    *)
        HOST_EXEEXT=
        HOST_DLLEXT=.so
        ;;
esac

# Re-create the configuration file
config_mk=$OUT_DIR/build/config.make
config_dir=$(dirname $config_mk)
mkdir -p "$config_dir" 2> $TMPL
if [ $? != 0 ] ; then
    echo "Can't create directory for build config file: $config_dir"
    cat $TMPL
    clean_exit
fi

log "Generate   : $config_mk"

echo "# This file was autogenerated by $PROGNAME. Do not edit !" > $config_mk
echo "HOST_OS     := $HOST_OS" >> $config_mk
echo "HOST_ARCH   := $HOST_ARCH" >> $config_mk
echo "HOST_CC     := $CC" >> $config_mk
echo "HOST_CXX    := $CXX" >> $config_mk
echo "HOST_LD     := $LD" >> $config_mk
echo "HOST_AR     := $AR" >> $config_mk
echo "HOST_OBJCOPY := $OBJCOPY" >> $config_mk
echo "HOST_WINDRES:= $WINDRES" >> $config_mk
echo "HOST_DUMPSYMS:= $DUMPSYMS" >> $config_mk
echo "OBJS_DIR    := $OUT_DIR" >> $config_mk
echo "" >> $config_mk
echo "HOST_PREBUILT_TAG := $HOST_TAG" >> $config_mk
echo "HOST_EXEEXT       := $HOST_EXEEXT" >> $config_mk
echo "HOST_DLLEXT       := $HOST_DLLEXT" >> $config_mk
echo "PREBUILT          := $ANDROID_PREBUILT" >> $config_mk
echo "PREBUILTS         := $ANDROID_PREBUILTS" >> $config_mk

echo "" >> $config_mk
echo "BUILD_EXEEXT      := $BUILD_EXEEXT" >> $config_mk
echo "BUILD_DLLEXT      := $BUILD_DLLEXT" >> $config_mk
echo "BUILD_AR          := $BUILD_AR" >> $config_mk
echo "BUILD_CC          := $BUILD_CC" >> $config_mk
echo "BUILD_CXX         := $BUILD_CXX" >> $config_mk
echo "BUILD_LD          := $BUILD_LD" >> $config_mk
echo "BUILD_OBJCOPY     := $BUILD_OBJCOPY" >> $config_mk
echo "BUILD_CFLAGS      := $BUILD_CFLAGS" >> $config_mk
echo "BUILD_LDFLAGS     := $BUILD_LDFLAGS" >> $config_mk
echo "BUILD_DUMPSYMS    := $DUMPSYMS" >> $config_mk

PWD=`pwd`
echo "SRC_PATH          := $PWD" >> $config_mk
echo "CONFIG_COREAUDIO  := $PROBE_COREAUDIO" >> $config_mk
echo "CONFIG_WINAUDIO   := $PROBE_WINAUDIO" >> $config_mk
echo "CONFIG_ESD        := $PROBE_ESD" >> $config_mk
echo "CONFIG_ALSA       := $PROBE_ALSA" >> $config_mk
echo "CONFIG_OSS        := $PROBE_OSS" >> $config_mk
echo "CONFIG_PULSEAUDIO := $PROBE_PULSEAUDIO" >> $config_mk
if [ "$QT_PREBUILTS_DIR" ]; then
    echo "QT_PREBUILTS_DIR  := $QT_PREBUILTS_DIR" >> $config_mk
    echo "EMULATOR_USE_SDL2 := false" >> $config_mk
    echo "EMULATOR_USE_QT   := true" >> $config_mk
else
    echo "SDL2_PREBUILTS_DIR := $SDL2_PREBUILTS_DIR" >> $config_mk
    echo "EMULATOR_USE_SDL2 := true" >> $config_mk
    echo "EMULATOR_USE_QT   := false" >> $config_mk
fi
if [ "$OPTION_GLES" = "angle" ] ; then
    echo "EMULATOR_USE_ANGLE := true" >> $config_mk
else
    echo "EMULATOR_USE_ANGLE := false" >> $config_mk
fi

echo "ZLIB_PREBUILTS_DIR := $ZLIB_PREBUILTS_DIR" >> $config_mk
echo "LIBPNG_PREBUILTS_DIR := $LIBPNG_PREBUILTS_DIR" >> $config_mk
echo "LIBXML2_PREBUILTS_DIR := $LIBXML2_PREBUILTS_DIR" >> $config_mk
echo "LIBCURL_PREBUILTS_DIR := $LIBCURL_PREBUILTS_DIR" >> $config_mk
echo "BREAKPAD_PREBUILTS_DIR := $BREAKPAD_PREBUILTS_DIR" >> $config_mk

if [ $OPTION_DEBUG = "yes" ] ; then
    echo "BUILD_DEBUG_EMULATOR := true" >> $config_mk
fi
echo "EMULATOR_EMUGL_SOURCES_DIR := $GLES_DIR" >> $config_mk
if [ "$OPTION_STRIP" = "yes" ]; then
    echo "EMULATOR_STRIP_BINARIES := true" >> $config_mk
fi
if [ "$OPTION_SYMBOLS" = "yes" ]; then
    echo "EMULATOR_GENERATE_SYMBOLS := true" >> $config_mk
fi

ANDROID_SDK_TOOLS_REVSION=
if [ "$ANDROID_SDK_TOOLS_REVISION" ] ; then
  echo "ANDROID_SDK_TOOLS_REVISION := $ANDROID_SDK_TOOLS_REVISION" >> $config_mk
fi

if [ "$config_mk" = "yes" ] ; then
    echo "" >> $config_mk
    echo "USE_MINGW := 1" >> $config_mk
    echo "HOST_OS   := windows" >> $config_mk
    echo "HOST_MINGW_VERSION := $MINGW_GCC_VERSION" >> $config_mk
fi

# Build the config-host.h file
#
config_h=$OUT_DIR/build/config-host.h
cat > $config_h <<EOF
/* This file was autogenerated by '$PROGNAME' */

#define CONFIG_QEMU_SHAREDIR   "/usr/local/share/qemu"

EOF

if [ "$HAVE_BYTESWAP_H" = "yes" ] ; then
  echo "#define CONFIG_BYTESWAP_H 1" >> $config_h
fi
if [ "$HAVE_MACHINE_BYTESWAP_H" = "yes" ] ; then
  echo "#define CONFIG_MACHINE_BSWAP_H 1" >> $config_h
fi
if [ "$HAVE_FNMATCH_H" = "yes" ] ; then
  echo "#define CONFIG_FNMATCH  1" >> $config_h
fi
echo "#define CONFIG_GDBSTUB  1" >> $config_h
echo "#define CONFIG_SLIRP    1" >> $config_h
echo "#define CONFIG_SKINS    1" >> $config_h
echo "#define CONFIG_TRACE    1" >> $config_h

if [ "$QT_PREBUILTS_DIR" ]; then
    echo "#define CONFIG_QT     1" >> $config_h
    echo "#undef CONFIG_SDL" >> $config_h
else
    echo "#undef CONFIG_QT" >> $config_mk
    echo "#define CONFIG_SDL    1" >> $config_h
fi

case "$HOST_OS" in
    windows)
        echo "#define CONFIG_WIN32  1" >> $config_h
        ;;
    *)
        echo "#define CONFIG_POSIX  1" >> $config_h
        ;;
esac

case "$HOST_OS" in
    linux)
        echo "#define CONFIG_KVM_GS_RESTORE 1" >> $config_h
        ;;
esac

# only Linux has fdatasync()
case "$HOST_OS" in
    linux)
        echo "#define CONFIG_FDATASYNC    1" >> $config_h
        ;;
esac

case "$HOST_OS" in
    linux|darwin)
        echo "#define CONFIG_MADVISE  1" >> $config_h
        ;;
esac

# the -nand-limits options can only work on non-windows systems
if [ "$HOST_OS" != "windows" ] ; then
    echo "#define CONFIG_NAND_LIMITS  1" >> $config_h
fi
echo "#define QEMU_VERSION    \"0.10.50\"" >> $config_h
echo "#define QEMU_PKGVERSION \"Android\"" >> $config_h
BSD=
case "$HOST_OS" in
    linux) CONFIG_OS=LINUX
    ;;
    darwin) CONFIG_OS=DARWIN
            BSD=1
    ;;
    freebsd) CONFIG_OS=FREEBSD
             BSD=1
    ;;
    windows) CONFIG_OS=WIN32
    ;;
    *) CONFIG_OS=$HOST_OS
esac

case $HOST_OS in
    linux|darwin)
        echo "#define CONFIG_IOVEC 1" >> $config_h
        ;;
esac

echo "#define CONFIG_$CONFIG_OS   1" >> $config_h
if [ "$BSD" ]; then
    echo "#define CONFIG_BSD       1" >> $config_h
    echo "#define O_LARGEFILE      0" >> $config_h
    echo "#define MAP_ANONYMOUS    MAP_ANON" >> $config_h
fi

case "$HOST_OS" in
    linux)
        echo "#define CONFIG_SIGNALFD       1" >> $config_h
        ;;
esac

echo "#define CONFIG_ANDROID       1" >> $config_h

log "Generate   : $config_h"

# Generate the QAPI headers and sources from qapi-schema.json
# Ideally, this would be done in our Makefiles, but as far as I
# understand, the platform build doesn't support a single tool
# that generates several sources files, nor the standalone one.
export PYTHONDONTWRITEBYTECODE=1
AUTOGENERATED_DIR=$OUT_DIR/build/qemu1-qapi-auto-generated
mkdir -p "$AUTOGENERATED_DIR"
python scripts/qapi-types.py qapi.types --output-dir=$AUTOGENERATED_DIR -b < qapi-schema.json
python scripts/qapi-visit.py --output-dir=$AUTOGENERATED_DIR -b < qapi-schema.json
python scripts/qapi-commands.py --output-dir=$AUTOGENERATED_DIR -m < qapi-schema.json
log "Generate   : $AUTOGENERATED_DIR"

clean_temp

echo "Ready to go. Type 'make' to build emulator"
