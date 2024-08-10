import std/unittest
import mike
import mike/common
import mike/cookies {.all.}
import std/options
import std/strtabs
import times

suite "Cookies to string":
  let date = "Wed, 21 Oct 2015 07:28:00 GMT".parse(httpDateFormat)
  test "Basic key/value":
    check $SetCookie(name: "foo", value: "bar") == "foo=bar; SameSite=Lax"

  test "With invalid vlaue":
    check $SetCookie(name: "foo", value: "fizz buzz") == "foo=fizz+buzz; SameSite=Lax"

  test "With expiry":
    check $SetCookie(name: "foo", value: "bar", expires: some date) == "foo=bar; Expires=" & date.format(httpDateFormat) & "; SameSite=Lax"

  test "With Max age":
    check $SetCookie(name: "foo", value: "bar", maxAge: some 1.hours) == "foo=bar; Max-Age=3600; SameSite=Lax"

  test "Max age takes precedence":
    check $SetCookie(name: "foo", value: "bar", maxAge: some 1.hours, expires: some date) == "foo=bar; Max-Age=3600; SameSite=Lax"

  test "All values":
    let fullSetCookie = SetCookie(
      name: "foo", value: "bar",
      maxAge: some 1.hours, expires: some date,
      domain: "example.com", path: "/",
      secure: true, httpOnly: true,
      sameSite: Strict
    )
    check $fullSetCookie == "foo=bar; Max-Age=3600; Domain=example.com; Path=/; Secure; HttpOnly; SameSite=Strict"


suite "Parse cookies":
  template checkCookies(input: string, values: openArray[(string, string)]) =
    var jar = newStringTable()
    input.parseCookies(jar)
    for (key, value) in values:
      check jar[key] == value

  test "Single cookie":
    checkCookies "name=value", {"name": "value"}

  test "Multiple cookies":
    checkCookies "PHPSESSID=298zf09hf012fh2; csrftoken=u32t4o3tb3gg43; _gat=1", {
      "PHPSESSID": "298zf09hf012fh2",
      "csrftoken": "u32t4o3tb3gg43",
      "_gat": "1"
    }

