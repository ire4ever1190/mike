import mike
import unittest, os
import utils


servePublic("tests/public", "static")
runServerInBackground()


suite "Static files":
  let
    testFilePath = "tests/public/test.html"
    testHtml = testFilePath.readFile()
  # Remove file to double check that files
  # are getting read from memory
  removeFile testFilePath
  test "Can get file":
    let resp = get("/static/test.html")
    check resp.code == Http200
    check resp.body == testHtml

  test "404 when file doesn't exist":
    check get("/static/doesntExist").code == Http404
    # TODO: Add tests for compression

  # Write back to future tests dont fail
  testFilePath.writeFile(testHtml)
