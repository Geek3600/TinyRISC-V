#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# This file is part of the GNU MCU Eclipse distribution.
#   (https://gnu-mcu-eclipse.github.io)
# Copyright (c) 2019 Liviu Ionescu.
#
# Permission to use, copy, modify, and/or distribute this software 
# for any purpose is hereby granted, under the terms of the MIT license.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Safety settings (see https://gist.github.com/ilg-ul/383869cbb01f61a51c4d).

if [[ ! -z ${DEBUG} ]]
then
  set ${DEBUG} # Activate the expand mode if DEBUG is anything but empty.
else
  DEBUG=""
fi

set -o errexit # Exit if command failed.
set -o pipefail # Exit if pipe failed.
set -o nounset # Exit if variable not set.

# Remove the initial space and instead use '\n'.
IFS=$'\n\t'

# -----------------------------------------------------------------------------
# Identify the script location, to reach, for example, the helper scripts.

build_script_path="$0"
if [[ "${build_script_path}" != /* ]]
then
  # Make relative path absolute.
  build_script_path="$(pwd)/$0"
fi

script_folder_path="$(dirname "${build_script_path}")"
script_folder_name="$(basename "${script_folder_path}")"

# =============================================================================

# Inner script to run inside Docker containers to build the 
# GNU MCU Eclipse RISC-V Embedded GCC distribution packages.

# For native builds, it runs on the host (macOS build cases,
# and development builds for GNU/Linux).

# -----------------------------------------------------------------------------

defines_script_path="${script_folder_path}/defs-source.sh"
echo "Definitions source script: \"${defines_script_path}\"."
source "${defines_script_path}"

# This file is generated by the host build script.
host_defines_script_path="${script_folder_path}/host-defs-source.sh"
echo "Host definitions source script: \"${host_defines_script_path}\"."
source "${host_defines_script_path}"

common_helper_functions_script_path="${script_folder_path}/helper/common-functions-source.sh"
echo "Common helper functions source script: \"${common_helper_functions_script_path}\"."
source "${common_helper_functions_script_path}"

container_functions_script_path="${script_folder_path}/helper/container-functions-source.sh"
echo "Container helper functions source script: \"${container_functions_script_path}\"."
source "${container_functions_script_path}"

container_libs_functions_script_path="${script_folder_path}/${CONTAINER_LIBS_FUNCTIONS_SCRIPT_NAME}"
echo "Container libs functions source script: \"${container_libs_functions_script_path}\"."
source "${container_libs_functions_script_path}"

container_app_functions_script_path="${script_folder_path}/${CONTAINER_APP_FUNCTIONS_SCRIPT_NAME}"
echo "Container app functions source script: \"${container_app_functions_script_path}\"."
source "${container_app_functions_script_path}"

# -----------------------------------------------------------------------------

if [ ! -z "#{DEBUG}" ]
then
  echo $@
fi

WITH_STRIP="y"
WITHOUT_MULTILIB=""
WITH_PDF="y"
WITH_HTML="n"
IS_DEVELOP=""
IS_DEBUG=""

LINUX_INSTALL_PATH=""
USE_GITS=""

JOBS=""

while [ $# -gt 0 ]
do

  case "$1" in

    --disable-strip)
      WITH_STRIP="n"
      shift
      ;;

    --without-pdf)
      WITH_PDF="n"
      shift
      ;;

    --with-pdf)
      WITH_PDF="y"
      shift
      ;;

    --without-html)
      WITH_HTML="n"
      shift
      ;;

    --with-html)
      WITH_HTML="y"
      shift
      ;;

    --jobs)
      JOBS=$2
      shift 2
      ;;

    --develop)
      IS_DEVELOP="y"
      shift
      ;;

    --debug)
      IS_DEBUG="y"
      WITH_STRIP="n"
      shift
      ;;

    # --- specific

    --linux-install-path)
      LINUX_INSTALL_PATH="$2"
      shift 2
      ;;

    --disable-multilib)
      WITHOUT_MULTILIB="y"
      shift
      ;;

    --use-gits)
      USE_GITS="y"
      shift
      ;;

    *)
      echo "Unknown action/option $1"
      exit 1
      ;;

  esac

done

if [ "${IS_DEBUG}" == "y" ]
then
  WITH_STRIP="n"
fi

# -----------------------------------------------------------------------------

start_timer

detect_container

prepare_xbb_env

prepare_xbb_extras

function add_linux_install_path()
{
  # Verify that the compiler is there.
  "${WORK_FOLDER_PATH}/${LINUX_INSTALL_PATH}/bin/${GCC_TARGET}-gcc" --version

  export PATH="${WORK_FOLDER_PATH}/${LINUX_INSTALL_PATH}/bin:${PATH}"
  echo ${PATH}

  export LD_LIBRARY_PATH="${WORK_FOLDER_PATH}/${LINUX_INSTALL_PATH}/bin:${LD_LIBRARY_PATH}"
  echo ${LD_LIBRARY_PATH}
}

# -----------------------------------------------------------------------------

README_OUT_FILE_NAME="README-${RELEASE_VERSION}.md"

APP_PREFIX_NANO="${INSTALL_FOLDER_PATH}/${APP_LC_NAME}-nano"

# The \x2C is a comma in hex; without this trick the regular expression
# that processes this string in the Makefile, silently fails and the 
# bfdver.h file remains empty.
BRANDING="${BRANDING}\x2C ${TARGET_BITS}-bit"
CFLAGS_OPTIMIZATIONS_FOR_TARGET="-ffunction-sections -fdata-sections -O2"
# Cannot use medlow with 64 bits, so all must be medany.
CFLAGS_OPTIMIZATIONS_FOR_TARGET+=" -mcmodel=medany"

BINUTILS_PROJECT_NAME="riscv-binutils-gdb"
GCC_PROJECT_NAME="riscv-none-gcc"
NEWLIB_PROJECT_NAME="riscv-newlib"
GDB_PROJECT_NAME="riscv-binutils-gdb"

MULTILIB_FLAGS=""

BINUTILS_PATCH=""
GDB_PATCH=""

# Redefine to "y" to create the LTO plugin links.
FIX_LTO_PLUGIN=""
if [ "${TARGET_PLATFORM}" == "darwin" ]
then
  LTO_PLUGIN_ORIGINAL_NAME="liblto_plugin.0.so"
  LTO_PLUGIN_BFD_PATH="lib/bfd-plugins/liblto_plugin.so"
elif [ "${TARGET_PLATFORM}" == "linux" ]
then
  LTO_PLUGIN_ORIGINAL_NAME="liblto_plugin.so.0.0.0"
  LTO_PLUGIN_BFD_PATH="lib/bfd-plugins/liblto_plugin.so"
elif [ "${TARGET_PLATFORM}" == "win32" ]
then
  LTO_PLUGIN_ORIGINAL_NAME="liblto_plugin-0.dll"
  LTO_PLUGIN_BFD_PATH="lib/bfd-plugins/liblto_plugin-0.dll"
fi

# Keep them in sync with combo archive content.
if [[ "${RELEASE_VERSION}" =~ 7\.2\.0-3-* ]]
then

  # ---------------------------------------------------------------------------

  # The default is:
  # rv32i-ilp32--c rv32im-ilp32--c rv32iac-ilp32-- rv32imac-ilp32-- rv32imafc-ilp32f-rv32imafdc- rv64imac-lp64-- rv64imafdc-lp64d--
  # Add 'rv32imaf-ilp32f--'. 
  GCC_MULTILIB=${GCC_MULTILIB:-"rv32i-ilp32--c rv32im-ilp32--c rv32iac-ilp32-- rv32imac-ilp32-- rv32imaf-ilp32f-- rv32imafc-ilp32f-rv32imafdc- rv64imac-lp64-- rv64imafdc-lp64d--"}

  GCC_MULTILIB_FILE=${GCC_MULTILIB_FILE:-"t-elf-multilib"}

  # ---------------------------------------------------------------------------

  BINUTILS_VERSION="2.29"
  # From gcc/BASE_VER
  GCC_VERSION="7.2.0"
  # From newlib/configure, VERSION=
  NEWLIB_VERSION="2.5.0"
  # From gdb/VERSION.in
  GDB_VERSION="8.0"

  # ---------------------------------------------------------------------------

  if [ "${USE_GITS}" != "y" ]
  then

    GH_RELEASE="7.2.0-3-20180506"
    BINUTILS_GH_RELEASE=${BINUTILS_GH_RELEASE:-"${GH_RELEASE}"}
    GCC_GH_RELEASE=${GCC_GH_RELEASE:-"${GH_RELEASE}"}
    NEWLIB_GH_RELEASE=${NEWLIB_GH_RELEASE:-"${GH_RELEASE}"}
    GDB_GH_RELEASE=${GDB_GH_RELEASE:-"${GH_RELEASE}"}

  else

    BINUTILS_GIT_BRANCH=${BINUTILS_GIT_BRANCH:-"riscv-binutils-2.29-gme"}
    # June 17, 2017
    BINUTILS_GIT_COMMIT=${BINUTILS_GIT_COMMIT:-"a8d8cd7ff85a945b30ddd484a4d7592af3ed8fbb"}

    GCC_GIT_BRANCH=${GCC_GIT_BRANCH:-"riscv-gcc-7.2.0-gme"}
    GCC_GIT_COMMIT=${GCC_GIT_COMMIT:-"ea82ccadd6c4906985249c52009deddc6b623b16"}

    NEWLIB_GIT_BRANCH=${NEWLIB_GIT_BRANCH:-"riscv-newlib-2.5.0-gme"}
    NEWLIB_GIT_COMMIT=${NEWLIB_GIT_COMMIT:-"325bec1e33fb0a1c30ce5a9aeeadd623f559ef1a"}

    GDB_SRC_FOLDER_NAME=${GDB_SRC_FOLDER_NAME:-"${BINUTILS_PROJECT_NAME}.git"}
    GDB_GIT_BRANCH=${GDB_GIT_BRANCH:-"${BINUTILS_GIT_BRANCH}"}
    GDB_GIT_COMMIT=${GDB_GIT_COMMIT:-"${BINUTILS_GIT_COMMIT}"}

  fi
  
  # ---------------------------------------------------------------------------

  ZLIB_VERSION="1.2.8"
  GMP_VERSION="6.1.2"
  MPFR_VERSION="3.1.6"
  MPC_VERSION="1.0.3"
  ISL_VERSION="0.18"
  LIBELF_VERSION="0.8.13"
  EXPAT_VERSION="2.2.5"
  LIBICONV_VERSION="1.15"
  XZ_VERSION="5.2.3"

  PYTHON_WIN_VERSION="2.7.13"

  # ---------------------------------------------------------------------------
elif [[ "${RELEASE_VERSION}" =~ 7\.2\.0-4-* ]]
then

  # ---------------------------------------------------------------------------

  # The default is:
  # rv32i-ilp32--c rv32im-ilp32--c rv32iac-ilp32-- rv32imac-ilp32-- rv32imafc-ilp32f-rv32imafdc- rv64imac-lp64-- rv64imafdc-lp64d--
  # Add 'rv32imaf-ilp32f--'. 
  GCC_MULTILIB=${GCC_MULTILIB:-"rv32i-ilp32--c rv32im-ilp32--c rv32iac-ilp32-- rv32imac-ilp32-- rv32imaf-ilp32f-- rv32imafc-ilp32f-rv32imafdc- rv64imac-lp64-- rv64imafdc-lp64d--"}

  GCC_MULTILIB_FILE=${GCC_MULTILIB_FILE:-"t-elf-multilib"}

  # ---------------------------------------------------------------------------

  BINUTILS_VERSION="2.29"
  # From gcc/BASE_VER
  GCC_VERSION="7.2.0"
  # From newlib/configure, VERSION=
  NEWLIB_VERSION="2.5.0"
  # From gdb/VERSION.in
  GDB_VERSION="8.0"

  # ---------------------------------------------------------------------------

  if [ "${USE_GITS}" != "y" ]
  then

    GH_RELEASE="7.2.0-4-20180606"
    BINUTILS_GH_RELEASE=${BINUTILS_GH_RELEASE:-"${GH_RELEASE}"}
    GCC_GH_RELEASE=${GCC_GH_RELEASE:-"${GH_RELEASE}"}
    NEWLIB_GH_RELEASE=${NEWLIB_GH_RELEASE:-"${GH_RELEASE}"}
    GDB_GH_RELEASE=${GDB_GH_RELEASE:-"${GH_RELEASE}"}

  else

    BINUTILS_GIT_BRANCH=${BINUTILS_GIT_BRANCH:-"riscv-binutils-2.29-gme"}
    # June 17, 2017
    BINUTILS_GIT_COMMIT=${BINUTILS_GIT_COMMIT:-"a8d8cd7ff85a945b30ddd484a4d7592af3ed8fbb"}

    GCC_GIT_BRANCH=${GCC_GIT_BRANCH:-"riscv-gcc-7.2.0-gme"}
    GCC_GIT_COMMIT=${GCC_GIT_COMMIT:-"ea82ccadd6c4906985249c52009deddc6b623b16"}

    NEWLIB_GIT_BRANCH=${NEWLIB_GIT_BRANCH:-"riscv-newlib-2.5.0-gme"}
    NEWLIB_GIT_COMMIT=${NEWLIB_GIT_COMMIT:-"325bec1e33fb0a1c30ce5a9aeeadd623f559ef1a"}

    GDB_SRC_FOLDER_NAME=${GDB_SRC_FOLDER_NAME:-"${BINUTILS_PROJECT_NAME}.git"}
    GDB_GIT_BRANCH=${GDB_GIT_BRANCH:-"${BINUTILS_GIT_BRANCH}"}
    GDB_GIT_COMMIT=${GDB_GIT_COMMIT:-"${BINUTILS_GIT_COMMIT}"}

  fi
  
  # ---------------------------------------------------------------------------

  ZLIB_VERSION="1.2.8"
  GMP_VERSION="6.1.2"
  MPFR_VERSION="3.1.6"
  MPC_VERSION="1.0.3"
  ISL_VERSION="0.18"
  LIBELF_VERSION="0.8.13"
  EXPAT_VERSION="2.2.5"
  LIBICONV_VERSION="1.15"
  XZ_VERSION="5.2.3"

  PYTHON_WIN_VERSION="2.7.13"

  # ---------------------------------------------------------------------------
elif [[ "${RELEASE_VERSION}" =~ 7\.3\.0-* ]]
then

  # WARNING: Experimental, do not use for releases!

  # ---------------------------------------------------------------------------

  # The default is:
  # rv32i-ilp32--c rv32im-ilp32--c rv32iac-ilp32-- rv32imac-ilp32-- rv32imafc-ilp32f-rv32imafdc- rv64imac-lp64-- rv64imafdc-lp64d--
  # Add 'rv32imaf-ilp32f--'. 
  GCC_MULTILIB=${GCC_MULTILIB:-"rv32i-ilp32--c rv32im-ilp32--c rv32iac-ilp32-- rv32imac-ilp32-- rv32imaf-ilp32f-- rv32imafc-ilp32f-rv32imafdc- rv64imac-lp64-- rv64imafdc-lp64d--"}

  GCC_MULTILIB_FILE=${GCC_MULTILIB_FILE:-"t-elf-multilib"}

  # ---------------------------------------------------------------------------

  BINUTILS_VERSION="2.29"
  # From gcc/BASE_VER
  GCC_VERSION="7.3.0"
  # From newlib/configure, VERSION=
  NEWLIB_VERSION="2.5.0"
  # From gdb/VERSION.in
  GDB_VERSION="8.0"

  # ---------------------------------------------------------------------------

  if [ "${USE_GITS}" != "y" ]
  then

    GH_RELEASE="7.3.0-1-20180506"
    BINUTILS_GH_RELEASE=${BINUTILS_GH_RELEASE:-"${GH_RELEASE}"}
    GCC_GH_RELEASE=${GCC_GH_RELEASE:-"${GH_RELEASE}"}
    NEWLIB_GH_RELEASE=${NEWLIB_GH_RELEASE:-"${GH_RELEASE}"}
    GDB_GH_RELEASE=${GDB_GH_RELEASE:-"${GH_RELEASE}"}

  else

    BINUTILS_GIT_BRANCH=${BINUTILS_GIT_BRANCH:-"riscv-binutils-2.29-gme"}
    # June 17, 2017
    BINUTILS_GIT_COMMIT=${BINUTILS_GIT_COMMIT:-"a8d8cd7ff85a945b30ddd484a4d7592af3ed8fbb"}

    GCC_GIT_BRANCH=${GCC_GIT_BRANCH:-"riscv-gcc-7.3.0-gme"}
    GCC_GIT_COMMIT=${GCC_GIT_COMMIT:-"6d6363ebaf0190dc5af3ff09bc5416d4228fdfa2"}

    NEWLIB_GIT_BRANCH=${NEWLIB_GIT_BRANCH:-"riscv-newlib-2.5.0-gme"}
    NEWLIB_GIT_COMMIT=${NEWLIB_GIT_COMMIT:-"325bec1e33fb0a1c30ce5a9aeeadd623f559ef1a"}

    GDB_SRC_FOLDER_NAME=${GDB_SRC_FOLDER_NAME:-"${BINUTILS_PROJECT_NAME}.git"}
    GDB_GIT_BRANCH=${GDB_GIT_BRANCH:-"${BINUTILS_GIT_BRANCH}"}
    GDB_GIT_COMMIT=${GDB_GIT_COMMIT:-"${BINUTILS_GIT_COMMIT}"}

  fi
  
  # ---------------------------------------------------------------------------

  ZLIB_VERSION="1.2.8"
  GMP_VERSION="6.1.2"
  MPFR_VERSION="3.1.6"
  MPC_VERSION="1.0.3"
  ISL_VERSION="0.18"
  LIBELF_VERSION="0.8.13"
  EXPAT_VERSION="2.2.5"
  LIBICONV_VERSION="1.15"
  XZ_VERSION="5.2.3"

  PYTHON_WIN_VERSION="2.7.13"

  # ---------------------------------------------------------------------------
elif [[ "${RELEASE_VERSION}" =~ 8\.1\.0-2-* ]]
then
  # This is similar to SiFive 20180928 release. (8.1.0-1 was 20180629, skipped)
  # ---------------------------------------------------------------------------

  # The default is:
  # rv32i-ilp32--c rv32im-ilp32--c rv32iac-ilp32-- rv32imac-ilp32-- rv32imafc-ilp32f-rv32imafdc- rv64imac-lp64-- rv64imafdc-lp64d--
  # Add 'rv32imaf-ilp32f--'. 
  GCC_MULTILIB=${GCC_MULTILIB:-"rv32i-ilp32--c rv32im-ilp32--c rv32iac-ilp32-- rv32imac-ilp32-- rv32imaf-ilp32f-- rv32imafc-ilp32f-rv32imafdc- rv64imac-lp64-- rv64imafdc-lp64d--"}

  GCC_MULTILIB_FILE=${GCC_MULTILIB_FILE:-"t-elf-multilib"}

  # ---------------------------------------------------------------------------

  BINUTILS_VERSION="2.30"
  # From gcc/BASE_VER
  GCC_VERSION="8.1.0"
  # From newlib/configure, VERSION=
  NEWLIB_VERSION="3.0.0"
  # From gdb/VERSION.in
  GDB_VERSION="8.2"

  # ---------------------------------------------------------------------------

  if [ "${USE_GITS}" != "y" ]
  then

    GH_RELEASE="8.1.0-2-20181019"
    BINUTILS_GH_RELEASE=${BINUTILS_GH_RELEASE:-"${GH_RELEASE}"}
    GCC_GH_RELEASE=${GCC_GH_RELEASE:-"${GH_RELEASE}"}
    NEWLIB_GH_RELEASE=${NEWLIB_GH_RELEASE:-"${GH_RELEASE}"}
    GDB_GH_RELEASE=${GDB_GH_RELEASE:-"${GH_RELEASE}-gdb"}

  else

    BINUTILS_GIT_BRANCH=${BINUTILS_GIT_BRANCH:-"riscv-binutils-2.30-gme"}
    # Oct 17, 2018
    BINUTILS_GIT_COMMIT=${BINUTILS_GIT_COMMIT:-"983075b97fb5e80ae26ac57410245e642f222bda"}

    GCC_GIT_BRANCH=${GCC_GIT_BRANCH:-"riscv-gcc-8.1.0-gme"}
    GCC_GIT_COMMIT=${GCC_GIT_COMMIT:-"151e02a6d1627f2aabb41e046295ecff387f64f3"}

    NEWLIB_GIT_BRANCH=${NEWLIB_GIT_BRANCH:-"riscv-newlib-3.0.0-gme"}
    NEWLIB_GIT_COMMIT=${NEWLIB_GIT_COMMIT:-"a6facff93404099561e7d7d5cd6bb37e4a1b698c"}

    GDB_SRC_FOLDER_NAME=${GDB_SRC_FOLDER_NAME:-"binutils-gdb.git"}
    GDB_GIT_BRANCH=${GDB_GIT_BRANCH:-"gnu-gdb-gme"}
    GDB_GIT_COMMIT=${GDB_GIT_COMMIT:-"ed0b2b7e2a7ef074b6e08a7035abab539a3bab3d"}

  fi
  

  # ---------------------------------------------------------------------------

  ZLIB_VERSION="1.2.8"
  GMP_VERSION="6.1.2"
  MPFR_VERSION="3.1.6"
  MPC_VERSION="1.0.3"
  ISL_VERSION="0.18"
  LIBELF_VERSION="0.8.13"
  EXPAT_VERSION="2.2.5"
  LIBICONV_VERSION="1.15"
  XZ_VERSION="5.2.3"

  PYTHON_WIN_VERSION="2.7.13"

  # ---------------------------------------------------------------------------
elif [[ "${RELEASE_VERSION}" =~ 8\.2\.0-2-* ]]
then
  # This is similar to SiFive 2019.02.0 release. (8.2.0-1, from 2018-12, was skipped)
  # https://github.com/sifive/freedom-tools/releases

  # Binutils 2.32 with SiFive CLIC patches
  # https://github.com/sifive/riscv-binutils-gdb/tree/164267155c96f91472a539ca78ac919993bc5b4e

  # GCC 8.2.0 with SiFive CLIC patches
  # https://github.com/sifive/riscv-gcc/tree/242abcaff697d0a1ea12dccc975465e1bfeb8331

  # GDB 8.2.90 from FSF 8.3.0 branch
  # riscv-gdb @ c8aa0bb (28 Feb 2019)
  # https://sourceware.org/git/?p=binutils-gdb.git
  # git://sourceware.org/git/binutils-gdb.git

  # Newlib 3.0.0 from SiFive branch
  # https://github.com/sifive/riscv-newlib/tree/42c2e3fb9f557d59b76d1a64bb6fb32707ff4530

  # ---------------------------------------------------------------------------

  # Inspired from SiFive
  # MULTILIBS_GEN := rv32e-ilp32e--c rv32em-ilp32e--c rv32eac-ilp32e-- rv32emac-ilp32e-- rv32i-ilp32--c rv32im-ilp32--c rv32iac-ilp32-- rv32imac-ilp32-- rv32imafc-ilp32f-rv32imafdc- rv32imafdc-ilp32d-- rv64imac-lp64-- rv64imafc-lp64f-rv64imafdc- rv64imafdc-lp64d--

  # Minimal list, for tests only. Pass it via the environment.
  # GCC_MULTILIB=${GCC_MULTILIB:-"rv32imac-ilp32-- rv64imac-lp64--"}

  # Old list.
  # GCC_MULTILIB=${GCC_MULTILIB:-"rv32i-ilp32--c rv32im-ilp32--c rv32iac-ilp32-- rv32imac-ilp32-- rv32imaf-ilp32f-- rv32imafc-ilp32f-rv32imafdc- rv64imac-lp64-- rv64imafdc-lp64d--"}
  
  # New extended list, based on SiFive list.
  # Added: rv32imaf-ilp32f--
  GCC_MULTILIB=${GCC_MULTILIB:-"rv32e-ilp32e--c rv32em-ilp32e--c rv32eac-ilp32e-- rv32emac-ilp32e-- rv32i-ilp32--c rv32im-ilp32--c rv32iac-ilp32-- rv32imac-ilp32-- rv32imaf-ilp32f-- rv32imafc-ilp32f-rv32imafdc- rv32imafdc-ilp32d-- rv64imac-lp64-- rv64imafc-lp64f-rv64imafdc- rv64imafdc-lp64d--"}

  GCC_MULTILIB_FILE=${GCC_MULTILIB_FILE:-"t-elf-multilib"}

  # ---------------------------------------------------------------------------

  BINUTILS_VERSION="2.32"
  # From gcc/BASE_VER
  GCC_VERSION="8.2.0"
  # From newlib/configure, VERSION=
  NEWLIB_VERSION="3.0.0"
  # From gdb/VERSION.in
  GDB_VERSION="8.2"

  FIX_LTO_PLUGIN="y"

  # ---------------------------------------------------------------------------

  if [ "${USE_GITS}" != "y" ]
  then

    # Be sure there is no `v`, it is added in the URL.
    GH_RELEASE="8.2.0-2"
    BINUTILS_GH_RELEASE=${BINUTILS_GH_RELEASE:-"${GH_RELEASE}"}
    GCC_GH_RELEASE=${GCC_GH_RELEASE:-"${GH_RELEASE}"}
    NEWLIB_GH_RELEASE=${NEWLIB_GH_RELEASE:-"${GH_RELEASE}"}
    # Same, with a `-gdb` suffix added.
    GDB_GH_RELEASE=${GDB_GH_RELEASE:-"${GH_RELEASE}-gdb"}

  else

    BINUTILS_GIT_BRANCH=${BINUTILS_GIT_BRANCH:-"sifive-binutils-2.32-gme"}
    # 16 April 2019
    BINUTILS_GIT_COMMIT=${BINUTILS_GIT_COMMIT:-"82b51c7b5087ddb77988287cd7a2dd8921331bfd"}

    GCC_GIT_BRANCH=${GCC_GIT_BRANCH:-"sifive-gcc-8.2.0-gme"}
    GCC_GIT_COMMIT=${GCC_GIT_COMMIT:-"0c7a874f0b6f452eeafde57731646e5f460187e4"}

    NEWLIB_GIT_BRANCH=${NEWLIB_GIT_BRANCH:-"sifive-newlib-3.0.0-gme"}
    NEWLIB_GIT_COMMIT=${NEWLIB_GIT_COMMIT:-"1975c561730cbd4b93c491eaadeb6c3b01a89447"}

    GDB_SRC_FOLDER_NAME=${GDB_SRC_FOLDER_NAME:-"binutils-gdb.git"}
    GDB_GIT_BRANCH=${GDB_GIT_BRANCH:-"sifive-gdb-8.2.90-gme"}
    GDB_GIT_COMMIT=${GDB_GIT_COMMIT:-"4f0bd4dde3c7b10c4f71e0c87d8707281c648671"}

  fi
  

  # ---------------------------------------------------------------------------

  ZLIB_VERSION="1.2.8"
  GMP_VERSION="6.1.2"
  MPFR_VERSION="3.1.6"
  MPC_VERSION="1.0.3"
  ISL_VERSION="0.18"
  LIBELF_VERSION="0.8.13"
  EXPAT_VERSION="2.2.5"
  LIBICONV_VERSION="1.15"
  XZ_VERSION="5.2.3"

  PYTHON_WIN_VERSION="2.7.13"

  BINUTILS_PATCH="binutils-gdb-${BINUTILS_VERSION}.patch"
  GDB_PATCH="binutils-gdb-${BINUTILS_VERSION}.patch"

  # ---------------------------------------------------------------------------
else
  echo "Unsupported version ${RELEASE_VERSION}."
  exit 1
fi

if [ "${USE_GITS}" != "y" ]
then

  # ---------------------------------------------------------------------------

  BINUTILS_SRC_FOLDER_NAME=${BINUTILS_SRC_FOLDER_NAME:-"${BINUTILS_PROJECT_NAME}-${BINUTILS_GH_RELEASE}"}
  BINUTILS_ARCHIVE_NAME=${BINUTILS_ARCHIVE_NAME:-"${BINUTILS_SRC_FOLDER_NAME}.tar.gz"}

  BINUTILS_ARCHIVE_URL=${BINUTILS_ARCHIVE_URL:-"https://github.com/gnu-mcu-eclipse/${BINUTILS_PROJECT_NAME}/archive/v${BINUTILS_GH_RELEASE}.tar.gz"}

  BINUTILS_GIT_URL=""

  # ---------------------------------------------------------------------------

  GCC_SRC_FOLDER_NAME=${GCC_SRC_FOLDER_NAME:-"${GCC_PROJECT_NAME}-${GCC_GH_RELEASE}"}
  GCC_ARCHIVE_NAME=${GCC_ARCHIVE_NAME:-"${GCC_SRC_FOLDER_NAME}.tar.gz"}

  GCC_ARCHIVE_URL=${GCC_ARCHIVE_URL:-"https://github.com/gnu-mcu-eclipse/${GCC_PROJECT_NAME}/archive/v${GCC_GH_RELEASE}.tar.gz"}

  GCC_GIT_URL=""

  # ---------------------------------------------------------------------------

  NEWLIB_SRC_FOLDER_NAME=${NEWLIB_SRC_FOLDER_NAME:-"${NEWLIB_PROJECT_NAME}-${NEWLIB_GH_RELEASE}"}
  NEWLIB_ARCHIVE_NAME=${NEWLIB_ARCHIVE_NAME:-"${NEWLIB_SRC_FOLDER_NAME}.tar.gz"}

  NEWLIB_ARCHIVE_URL=${NEWLIB_ARCHIVE_URL:-"https://github.com/gnu-mcu-eclipse/${NEWLIB_PROJECT_NAME}/archive/v${NEWLIB_GH_RELEASE}.tar.gz"}

  NEWLIB_GIT_URL=""

  # ---------------------------------------------------------------------------

  GDB_SRC_FOLDER_NAME=${GDB_SRC_FOLDER_NAME:-"${GDB_PROJECT_NAME}-${GDB_GH_RELEASE}"}
  GDB_ARCHIVE_NAME=${GDB_ARCHIVE_NAME:-"${GDB_SRC_FOLDER_NAME}.tar.gz"}

  GDB_ARCHIVE_URL=${GDB_ARCHIVE_URL:-"https://github.com/gnu-mcu-eclipse/${GDB_PROJECT_NAME}/archive/v${GDB_GH_RELEASE}.tar.gz"}

  GDB_GIT_URL=""

  # ---------------------------------------------------------------------------
else
  # ---------------------------------------------------------------------------

  BINUTILS_SRC_FOLDER_NAME=${BINUTILS_SRC_FOLDER_NAME:-"${BINUTILS_PROJECT_NAME}.git"}

  BINUTILS_GIT_URL=${BINUTILS_GIT_URL:-"https://github.com/gnu-mcu-eclipse/riscv-binutils-gdb.git"}

  BINUTILS_ARCHIVE_URL=""

  # ---------------------------------------------------------------------------

  GCC_SRC_FOLDER_NAME=${GCC_SRC_FOLDER_NAME:-"${GCC_PROJECT_NAME}.git"}

  GCC_GIT_URL=${GCC_GIT_URL:-"https://github.com/gnu-mcu-eclipse/riscv-none-gcc.git"}

  GCC_ARCHIVE_URL=""

  # ---------------------------------------------------------------------------

  NEWLIB_SRC_FOLDER_NAME=${NEWLIB_SRC_FOLDER_NAME:-"${NEWLIB_PROJECT_NAME}.git"}
    
  NEWLIB_GIT_URL=${NEWLIB_GIT_URL:-"https://github.com/gnu-mcu-eclipse/riscv-newlib.git"}

  NEWLIB_ARCHIVE_URL=""

  # ---------------------------------------------------------------------------

  # Pre 8.x builds define it to reuse the binutils repo.
  GDB_SRC_FOLDER_NAME=${GDB_SRC_FOLDER_NAME:-"binutils-gdb.git"}

  GDB_GIT_URL=${GDB_GIT_URL:-"https://github.com/gnu-mcu-eclipse/riscv-binutils-gdb.git"}

  GDB_ARCHIVE_URL=""

  # ---------------------------------------------------------------------------
fi

# -----------------------------------------------------------------------------


BINUTILS_FOLDER_NAME="binutils-${BINUTILS_VERSION}"
GCC_FOLDER_NAME="gcc-${GCC_VERSION}"
NEWLIB_FOLDER_NAME="newlib-${NEWLIB_VERSION}"
GDB_FOLDER_NAME="gdb-${GDB_VERSION}"

# Note: The 5.x build failed with various messages.

if [ "${WITHOUT_MULTILIB}" == "y" ]
then
  MULTILIB_FLAGS="--disable-multilib"
fi

if [ "${TARGET_ARCH}" == "x32" ]
then
  PYTHON_WIN=python-"${PYTHON_WIN_VERSION}"
elif [ "${TARGET_ARCH}" == "x64" ]
then
  PYTHON_WIN=python-"${PYTHON_WIN_VERSION}".amd64
fi

PYTHON_WIN_PACK="${PYTHON_WIN}".msi
PYTHON_WIN_URL="https://www.python.org/ftp/python/${PYTHON_WIN_VERSION}/${PYTHON_WIN_PACK}"

# -----------------------------------------------------------------------------

echo
echo "Here we go..."
echo

if [ "${TARGET_PLATFORM}" == "win32" ]
then
  # The Windows GDB needs some headers from the Python distribution.
  download_python_win
fi

# -----------------------------------------------------------------------------
# Build dependent libraries.

# For better control, without it some components pick the lib packed 
# inside the archive.
do_zlib

# The classical GCC libraries.
do_gmp
do_mpfr
do_mpc
do_isl

# More libraries.
do_libelf
do_expat
do_libiconv
do_xz

# -----------------------------------------------------------------------------

# The task descriptions are from the ARM build script.

# Task [III-0] /$HOST_NATIVE/binutils/
# Task [IV-1] /$HOST_MINGW/binutils/
do_binutils
# copy_dir to libs included above

if [ "${TARGET_PLATFORM}" != "win32" ]
then

  # Task [III-1] /$HOST_NATIVE/gcc-first/
  do_gcc_first

  # Task [III-2] /$HOST_NATIVE/newlib/
  do_newlib ""
  # Task [III-3] /$HOST_NATIVE/newlib-nano/
  do_newlib "-nano"

  # Task [III-4] /$HOST_NATIVE/gcc-final/
  do_gcc_final ""

  # Task [III-5] /$HOST_NATIVE/gcc-size-libstdcxx/
  do_gcc_final "-nano"

else

  # Task [IV-2] /$HOST_MINGW/copy_libs/
  copy_linux_libs

  # Task [IV-3] /$HOST_MINGW/gcc-final/
  do_gcc_final ""

fi

# Task [III-6] /$HOST_NATIVE/gdb/
# Task [IV-4] /$HOST_MINGW/gdb/
do_gdb ""
do_gdb "-py"
# Python3 support not yet functional.
# do_gdb "-py3"

# Task [III-7] /$HOST_NATIVE/build-manual
# Nope, the build process is different.

# -----------------------------------------------------------------------------

# Task [III-8] /$HOST_NATIVE/pretidy/
# Task [IV-5] /$HOST_MINGW/pretidy/
tidy_up

# Task [III-9] /$HOST_NATIVE/strip_host_objects/
# Task [IV-6] /$HOST_MINGW/strip_host_objects/
if [ "${WITH_STRIP}" == "y" ]
then
  strip_binaries
fi

# Must be done after gcc 2 make install, otherwise some wrong links
# are created in libexec.
# Must also be done after strip binaries, since strip after patchelf
# damages the binaries.
prepare_app_folder_libraries "${APP_PREFIX}"

if [ "${WITH_STRIP}" == "y" -a "${TARGET_PLATFORM}" != "win32" ]
then
  # Task [III-10] /$HOST_NATIVE/strip_target_objects/
  strip_libs
fi

final_tunings

# Task [IV-7] /$HOST_MINGW/installation/
# Nope, no setup.exe.

# Task [III-11] /$HOST_NATIVE/package_tbz2/
# Task [IV-8] /Package toolchain in zip format/

# -----------------------------------------------------------------------------

check_binaries

copy_distro_files

create_archive

# Change ownership to non-root Linux user.
fix_ownership

# -----------------------------------------------------------------------------

# Final checks.
# To keep everything as pristine as possible, run tests
# only after the archive is packed.
run_binutils
run_gcc
run_gdb

if [  "${TARGET_PLATFORM}" != "win32" ]
then
  run_gdb "-py"
fi

# -----------------------------------------------------------------------------

stop_timer

exit 0

# -----------------------------------------------------------------------------
