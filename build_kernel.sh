#!/bin/bash

#u can use zyc clang 14 if u're unsure what toolchain to use. goodluck building sir
#edit the zyc clang directory name accordingly to ur toolchain.

export CROSS_COMPILE=~/zyc-clang/bin/aarch64-linux-gnu-
export LD=~/zyc-clang/bin/ld.lld
export OBJCOPY=~/zyc-clang/bin/llvm-objcopy
export AS=~/zyc-clang/bin/llvm-as
export NM=~/zyc-clang/bin/llvm-nm
export STRIP=~/zyc-clang/bin/llvm-strip
export OBJDUMP=~/zyc-clang/bin/llvm-objdump
export READELF=~/zyc-clang/bin/llvm-readelf
export CC=~/zyc-clang/bin/clang
export CROSS_COMPILE_ARM32=~/zyc-clang/bin/arm-linux-gnueabi-
export ARCH=arm64
export ANDROID_MAJOR_VERSION=r

export KCFLAGS=' -w -pipe -O3'
export KCPPFLAGS=' -O3'
export CONFIG_SECTION_MISMATCH_WARN_ONLY=y

make -C $(pwd) O=$(pwd)/out KCFLAGS=' -w -pipe -O3' CONFIG_SECTION_MISMATCH_WARN_ONLY=y clean -j$(nproc) && make -C $(pwd) O=$(pwd)/out KCFLAGS='-w -O3' CONFIG_SECTION_MISMATCH_WARN_ONLY=y mrproper -j$(nproc)
make -C $(pwd) O=$(pwd)/out KCFLAGS=' -w -pipe -O3' CONFIG_SECTION_MISMATCH_WARN_ONLY=y -j$(nproc) a32_vigus_defconfig
make -s -C $(pwd) O=$(pwd)/out KCFLAGS=' -w -pipe -O3' CONFIG_SECTION_MISMATCH_WARN_ONLY=y -j$(nproc)
