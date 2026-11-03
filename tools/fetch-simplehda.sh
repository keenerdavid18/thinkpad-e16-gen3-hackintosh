#!/bin/zsh
# Downloads SimpleHDA 1.0.0 (laobamac) into EFI/OC/Kexts. Not shipped in this repo because it
# carries Apple's AppleHDA.kext inside it. SimpleHDA puts AppleHDA back on macOS Tahoe (Apple
# removed it in 26), which AppleALC needs for the internal speakers and headphone jack.
#   zsh tools/fetch-simplehda.sh
set -e
ROOT=${0:A:h:h}
URL=https://github.com/laobamac/SimpleHDA/releases/download/v1.0.0/SimpleHDA-Tahoe-v1.0.0-RELEASE.zip
ZIP_SHA=89198256664078c91155d673ee7cebb08134dad1b71d5e34b0aa4ef0d4877f8f
BIN_SHA=f74c9dbddf43266c97c5f72cd76498bce1d6b5bd3731a947be62f1378b4c7954
TMP=$(mktemp -d)
curl -fL -o $TMP/s.zip $URL
[[ $(shasum -a 256 $TMP/s.zip | cut -d' ' -f1) == $ZIP_SHA ]] || { echo "zip checksum mismatch"; exit 1; }
unzip -q $TMP/s.zip -d $TMP
K=$TMP/SimpleHDA-Tahoe-v1.0.0-RELEASE/SimpleHDA.kext
[[ $(shasum -a 256 $K/Contents/MacOS/SimpleHDA | cut -d' ' -f1) == $BIN_SHA ]] || { echo "kext checksum mismatch"; exit 1; }
rm -rf $ROOT/EFI/OC/Kexts/SimpleHDA.kext
cp -R $K $ROOT/EFI/OC/Kexts/
rm -rf $TMP
echo "installed $ROOT/EFI/OC/Kexts/SimpleHDA.kext"
