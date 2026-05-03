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
export ARCH=arm64

export KCFLAGS=' -w -pipe -O3'
export KCPPFLAGS=' -O3'
export CONFIG_SECTION_MISMATCH_WARN_ONLY=y

#setup configs directory
export CFGDIR=arch/arm64/configs

rm -rf $CFGDIR/compiled_defconfig
make -C $(pwd) O=$(pwd)/out clean -j$(nproc) && make -C $(pwd) O=$(pwd)/out mrproper -j$(nproc)
clear
 
read -p "`echo -e 'thanks for building slmkernel \ntell what device you wanna build for 💩💩 \nsupported devices: a22, a32, m32(experimental), f22(experimental), m22(very experimental)  '`" choice
case "$choice" in 
  a22|A22 ) export DEVICE="a22";;
  a32|A32 ) export DEVICE="a32";;
  m32|M32 ) export DEVICE="m32";;
  f22|F22 ) export DEVICE="f22";;
  m22|M22 ) export DEVICE="m22";;
  * ) echo "u made a typo or $choice not supported yet srry 💩" && exit;;
esac

#edit perf.config to battery.config to disable perf tweaks, dont use them at the same time!
#add $CFGDIR/ksu.config at the end before ">" for ksu integration(optional)
#example: build m22 battery life oriented karnal with ksu: $CFGDIR/mt6768_slm_defconfig $CFGDIR/"$DEVICE".config $CFGDIR/battery.config $CFGDIR/ksu.config
cat $CFGDIR/mt6768_slm_defconfig $CFGDIR/"$DEVICE".config $CFGDIR/perf.config > $CFGDIR/compiled_defconfig

#selinux control it by here
echo "
# CONFIG_ALWAYS_ENFORCE is not set
CONFIG_ALWAYS_PERMISSIVE=y
" >> $CFGDIR/compiled_defconfig

make -C $(pwd) O=$(pwd)/out -j$(nproc) compiled_defconfig
make -s -C $(pwd) O=$(pwd)/out -j$(nproc)
echo "u (tried to) built for: $DEVICE"

#only for me delete if u want 💩💩💩💩
read -p "copy to kernal directory? (are u vigus?) y/n   " choice
case "$choice" in 
  y|Y ) cp out/arch/arm64/boot/Image ~/Downloads/buildkernal/Image;;
  n|N ) echo "k";;
  * ) echo "nvm";;
esac
