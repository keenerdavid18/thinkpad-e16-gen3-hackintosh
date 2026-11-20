#!/bin/zsh
# Open iPhone Mirroring with vtbgra.dylib loaded (decoder output forced to BGRA). Quits a running copy first.
LIB="$HOME/Library/Application Support/E16Mirroring/vtbgra.dylib"
[[ -f $LIB ]] || { print "missing $LIB"; exit 1; }
osascript -e 'quit app "iPhone Mirroring"' 2>/dev/null; sleep 1
launchctl setenv DYLD_INSERT_LIBRARIES "$LIB"
open -a "iPhone Mirroring"
sleep 4
launchctl unsetenv DYLD_INSERT_LIBRARIES
