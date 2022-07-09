const above16 = (NimMajor, NimMinor, NimPatch) >= (1, 6, 0)
when above16:
  {.hint[DuplicateModuleImport]: off.}
include helpers/request
include helpers/response
include helpers/context
when above16:
  {.hint[DuplicateModuleImport]: on.}
