#!/bin/zsh
# build.sh: builds the NootedGreen.kext shipped in EFI/OC/Kexts (Iris Xe acceleration + the laptop's HDMI port +
# USB-C DisplayPort alt mode) from source, with only the Xcode Command Line Tools.
#   zsh src/nootedgreen/build.sh        -> src/nootedgreen/build/NootedGreen.kext
# Steps: clone JulioNectar/Hackintosh-XPS13Plus-IrisXe-Tahoe at 24450b4 (the graphics stack this EFI follows), apply
#   0001-vostroxe-xe-hdmi13.diff  henriquejsza/VostroXe's NootedGreen changes since 6f03560 (XE-HDMI13 etc.)
#   0002-usbc-dp-alt-mode.diff    USB-C DP alt mode for ADL-P/RPL-P on the TGL framebuffer (this repo, -ngreentc1)
# and run the reference's own build-nootedgreen.sh. Toolchain differences mean the result is not byte-identical to
# the shipped kext; behaviour is the same.
set -e
here=${0:A:h}
work=$here/build/ref
REF=https://github.com/JulioNectar/Hackintosh-XPS13Plus-IrisXe-Tahoe.git
COMMIT=24450b476d7ca025b83c85d7b8362caf3234d2f2
mkdir -p $here/build
if [[ ! -d $work/.git ]]; then git clone $REF $work; fi
git -C $work checkout -q -f $COMMIT
git -C $work clean -q -fd src
git -C $work apply $here/0001-vostroxe-xe-hdmi13.diff
git -C $work apply $here/0002-usbc-dp-alt-mode.diff
(cd $work && zsh build-nootedgreen.sh)
rm -rf $here/build/NootedGreen.kext
cp -R $work/build/NootedGreen.kext $here/build/NootedGreen.kext
print "built $here/build/NootedGreen.kext - copy it to EFI/OC/Kexts/NootedGreen.kext"
