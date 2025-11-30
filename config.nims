when defined(testing):
  --passC:"-fsanitize=address"
  --passL:"-fsanitize=address"

# begin Nimble config (version 2)
--noNimblePath
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config
