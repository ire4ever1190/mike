import mike
import unittest, os
import utils


servePublic("tests/public", "static", staticFiles = true)
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

  test "Content type is set":
    check get("/static/index.html").headers["Content-Type"] == "text/html"

  test "HEAD only sends headers":
    let
      getResp = get("/static/test.html")
      headResp = head("/static/test.html")
    check getResp.headers == headResp.headers
  # Write back to future tests dont fail
  testFilePath.writeFile(testHtml)
