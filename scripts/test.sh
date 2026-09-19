#!/bin/sh
# Only the Command Line Tools are installed (no Xcode.app), so swift test
# cannot find Testing.framework or its interop dylib without these paths.
CLT=/Library/Developer/CommandLineTools/Library/Developer
exec swift test \
  -Xswiftc -F"$CLT/Frameworks" \
  -Xlinker -F"$CLT/Frameworks" \
  -Xlinker -rpath -Xlinker "$CLT/Frameworks" \
  -Xlinker -rpath -Xlinker "$CLT/usr/lib" \
  "$@"
