#!/bin/bash

#u can use zyc clang 14 if u're unsure what toolchain to use. https://github.com/ZyCromerZ/Clang/releases/tag/14.0.6-20250704-release
# goodluck building sir
# gore ubuntu 25.10 error fix: sudo ln -s /lib/x86_64-linux-gnu/libxml2.so.16 /lib/x86_64-linux-gnu/libxml2.so.2
#edit the zyc clang directory name accordingly to ur toolchain.
export TC=/home/vigus/zyc-clang

export CROSS_COMPILE=$TC/bin/aarch64-linux-gnu-
export LD=$TC/bin/ld.lld
export OBJCOPY=$TC/bin/llvm-objcopy
export AS=$TC/bin/llvm-as
export NM=$TC/bin/llvm-nm
export STRIP=$TC/bin/llvm-strip
export OBJDUMP=$TC/bin/llvm-objdump
export READELF=$TC/bin/llvm-readelf
export CC=$TC/bin/clang
export CROSS_COMPILE_ARM32=$TC/bin/arm-linux-gnueabi-
export ARCH=arm64
export ANDROID_MAJOR_VERSION=r

export KCFLAGS=' -w -pipe -O3'
export KCPPFLAGS=' -O3'
export CONFIG_SECTION_MISMATCH_WARN_ONLY=y

make -C $(pwd) O=$(pwd)/out clean -j$(nproc) && make -C $(pwd) O=$(pwd)/out mrproper -j$(nproc)
clear
 
read -p "`echo -e 'thanks for building slmkernel \ntell what device you wanna build for 💩💩 \nsupported devices: a22, a32  '`" choice
case "$choice" in 
  a22|A22 ) export DEVICE="a22";;
  a32|A32 ) export DEVICE="a32";;
  * ) echo "u made a typo or $choice not supported yet srry 💩" && exit;;
esac

make -C $(pwd) O=$(pwd)/out -j$(nproc) "$DEVICE"_slm_defconfig
make -s -C $(pwd) O=$(pwd)/out KCFLAGS=' -w -pipe -O3' CONFIG_SECTION_MISMATCH_WARN_ONLY=y -j$(nproc)
echo "$DEVICE"

#only for me delete if u want 💩💩💩💩
read -p "copy to kernal directory? (are u vigus?) y/n   " choice
case "$choice" in 
  y|Y ) cp out/arch/arm64/boot/Image ~/Downloads/buildkernal/Image;;
  n|N ) echo "k";;
  * ) echo "nvm";;
esac
