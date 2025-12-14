when defined(testing):
  --passC:"-fsanitize=address -g"
  --passL:"-fsanitize=address"
  --debugger:native
switch("define", "chronicles_sinks=textblocks")

# begin Nimble config (version 2)
--noNimblePath
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config
