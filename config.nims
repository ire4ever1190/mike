when defined(testing):
  --passC:"-fsanitize=address -g -static-libasan"
  --passL:"-fsanitize=address"
  --debugger:native

# begin Nimble config (version 2)
--noNimblePath
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config
