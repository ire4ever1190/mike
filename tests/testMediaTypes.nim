import std/unittest

import mike/types/mediaTypes

suite "Parsing":
  test "Can parse basic type":
    let json = initMediaType("application/json")
    check json.family == "application"
    check json.subtype == "json"
    check json.params.len == 0

  test "Can parse parameters":
    let multipart = initMediaType("multipart/form-data; boundary=boundaryString")
    check multipart.family == "multipart"
    check multipart.subtype == "form-data"
    check multipart.params["boundary"] == "boundaryString"

  test "Form multipart, real world example":
    let multipart = initMediaType("multipart/form-data; boundary=4292486321577947087")
    check multipart <= initMediaType("multipart/form-data")
    check "boundary" in multipart.params

suite "Subtype check":
  test "Equal":
    check initMediaType("application/json; foo=bar") <= initMediaType("application/json")
