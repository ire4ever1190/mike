import ../context
import std/[
    strtabs,
    httpcore,
    parseutils,
    strformat,
    strutils
]
type
    # Handler* = tuple[constructor: proc (): Context, handlers: seq[AsyncHandler]]
    Handler* = seq[AsyncHandler]
    MappingError* = object of ValueError

    RoutingResult*[T] = object
        pathParams*: StringTableRef
        queryParams*: StringTableRef
        status*: bool
        handler*: T

    HttpRouter = concept router
        ## Interface that a router needs to implement
        router.route(HttpMethod, string): RoutingResult[Handler] # Finds a handler from a context
        router.map(HttpMethod, string, Handler)       # Maps a handler to a url

const
    paramStart* = ':'
    pathSeparator* = '/'
    greedyMatch* = '*'
    specialCharacters* = {pathSeparator, paramStart, greedyMatch}
    allowedCharacters* = {'a'..'z', 'A'..'Z', '0'..'9', '-', '.', '_', '~'} + specialCharacters

func getPathAndQuery*(url: string): tuple[path, query: string] {.inline.} =
    ## Returns the path and query string from a url
    let pathLength = url.parseUntil(result.path, '?')
    if pathLength != url.len():
        result.query = url[pathLength + 1 .. ^1]

func ensureCorrectRoute*(path: string): string {.raises: [MappingError], inline.} =
    ## Checks that the route doesn't have any illegal characters and removes any trailing/leading slashes
    for character in path.items():
        if character notin allowedCharacters:
            raise newException(MappingError, fmt"The character {character} is not allowed in the path. Please only use alphanumeric or - . _ ~ /")

    result = path
    if result.len == 1 and result[0] == '/':
        return

    if result[^1] == '/': # Remove last slash
        result.removeSuffix('/')

    if result[0] != '/': # Add in first slash if needed
        result.insert("/")