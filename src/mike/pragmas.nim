## Contains pragmas used for the API. Mostly for adding metadata to props

template name*(useName: string) {.pragma.}
  ## Makes a context hook parse a value using a different name
  ## ```nim
  ## proc getIds(auth {.name: "Authorization".}: Header[string]) =
  ##   # Will get the `auth` header using the `Authorization` key
  ## ```

