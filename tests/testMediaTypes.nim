import mike/types/mediaTypes

suite "Parsing":
  test "Can parse basic type":
    let json = initMediaType("application/json")
    check json.family == "application"
    check json.subtype == "json"
    check json.params == 0

  test "Can parse parameters":
    let multipart = initMediaType("multipart/form-data; boundary=boundaryString")
    check multipart.family == "multipart"
    check multipart.subtype == "form-data"
    check multipart.params["boundary"] == "boundaryString"
