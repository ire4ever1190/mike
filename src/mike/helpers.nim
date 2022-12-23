const above16 = (NimMajor, NimMinor, NimPatch) >= (1, 6, 0)

##[
  Helpers that make life easier for working with requests and reponses
]##

when above16:
  {.hint[DuplicateModuleImport]: off.}
include helpers/request
include helpers/response
include helpers/context
include helpers/auth
when above16:
  {.hint[DuplicateModuleImport]: on.}
