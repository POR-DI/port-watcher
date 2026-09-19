#!/bin/sh
# Only the Command Line Tools are installed (no Xcode.app), so swift test
# cannot find Testing.framework or its interop dylib without these paths.
# With Xcode installed, plain swift test works and these paths must not be used.
CLT=/Library/Developer/CommandLineTools/Library/Developer
if [ "$(xcode-select -p)" != "/Library/Developer/CommandLineTools" ]; then
  exec swift test "$@"
fi
exec swift test \
  -Xswiftc -F"$CLT/Frameworks" \
  -Xlinker -F"$CLT/Frameworks" \
  -Xlinker -rpath -Xlinker "$CLT/Frameworks" \
  -Xlinker -rpath -Xlinker "$CLT/usr/lib" \
  "$@"
