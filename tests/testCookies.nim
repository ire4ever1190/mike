import std/unittest
import mike/cookies
import mike/common
import std/options
import std/sequtils
import times

suite "Cookies to string":
  let date = "Wed, 21 Oct 2015 07:28:00 GMT".parse(httpDateFormat)
  test "Basic key/value":
    check $Cookie(name: "foo", value: "bar") == "foo=bar; SameSite=Lax"

  test "With expiry":
    check $Cookie(name: "foo", value: "bar", expires: some date) == "foo=bar; Expires=" & date.format(httpDateFormat) & "; SameSite=Lax"

  test "With Max age":
    check $Cookie(name: "foo", value: "bar", maxAge: some 1.hours) == "foo=bar; Max-Age=3600; SameSite=Lax"

  test "Max age takes precedence":
    check $Cookie(name: "foo", value: "bar", maxAge: some 1.hours, expires: some date) == "foo=bar; Max-Age=3600; SameSite=Lax"

  test "All values":
    let fullCookie = Cookie(
      name: "foo", value: "bar",
      maxAge: some 1.hours, expires: some date,
      domain: "example.com", path: "/",
      secure: true, httpOnly: true,
      sameSite: Strict
    )
    check $fullCookie == "foo=bar; Max-Age=3600; Domain=example.com; Path=/; Secure; HttpOnly; SameSite=Strict"


suite "Parse cookies":
  proc checkCookies(input: string, values: openArray[(string, string)]) =
    let cookies = input.parseCookies()
    for (actual, expected) in zip(cookies, values):
      check actual.name == expected[0]
      check actual.value == expected[1]

  test "Single cookie":
    checkCookies "name=value", {"name": "value"}

  test "Multiple cookies":
    checkCookies "PHPSESSID=298zf09hf012fh2; csrftoken=u32t4o3tb3gg43; _gat=1", {
      "PHPSESSID": "298zf09hf012fh2",
      "csrftoken": "u32t4o3tb3gg43",
      "_gat": "1"
    }
