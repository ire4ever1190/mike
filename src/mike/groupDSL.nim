
type
    Group = object
        path: string
        children: seq[Group]

func joinPath(parent, child: string): string {.compileTime.} =
    ## Version of join path that works for strings instead of uris.
    ## It has a / at the start but not at the end
    ## Isn't optimised but it works and only runs at compile time.
    for part in parent.split("/") & child.split("/"):
        if part != "":
            result &= "/" & part

func findMethod(input: string): HttpMethod =
    ## parseEnum is broken on stable so this
    ## basic enum finder is used instead
    for meth in HttpMethod:
        if $meth == input:
            return meth

func newGroup(path: string): Group =
    ## Starts a new group
    Group(
        children: newSeq[Group](),
        path: path
    )


macro group*(path: static[string], handler: typed): untyped =
    result = newStmtList()
    var groupRoutes: seq[
        tuple[
            path: string,
            verb: HttpMethod, # the name of the call e.g. `get` or `post`
            call: NimNode, # The full call
        ]
    ]
    var middlewares: seq[
        tuple[
            ident: NimNode,
            position: HandlerType # Pre or Post
        ]
    ]
    for node in handler:
        case node.kind
            of nnkCall, nnkCommand:
                let call = $node[0]
                if call in HttpMethods:
                    var routePath = if node[1].kind == nnkStrLit:
                                    path.joinPath(node[1].strVal())
                                else:
                                    path
                    if node[1].kind != nnkStrLit:
                        # If the node doesn't contain a path then it is just a method handler
                        # for the groups current path
                        node.insert(1, newStrLitNode routePath)
                    # parseEnum is broken on stable
                    # so this basic implementation is used instead
                    # TODO add check if this fails
                    let verb = findMethod(node[0].strVal().toUpperAscii())
                    var call = node
                    call[1] = newStrLitNode routePath
                    groupRoutes &= (path: routePath, verb: verb, call: call)
                elif call == "group":
                    # if node[1].kind != nnkStrLit:
                    #     # If you want to seperate the groups to have middlewares only
                    #     # apply to certain routes then you can do this
                    #     # Probably isn't the cleanest though
                    #     node.insert(1, newStrLitNode path)
                    echo node.treeRepr
                    node[1] = newStrLitNode path.joinPath(node[1].strVal())
                    result &= node
            of nnkIdent:
                middlewares &= (
                    ident: node,
                    position: if groupRoutes.len == 0: Pre else: Post
                )
            else: discard
    for route in groupRoutes:
        let
            path = route.path
            verb = route.verb
        # Add all the middlewares to the route
        for middleware in middlewares:
            let
                position = middleware.position
                ident = middleware.ident
            result.add quote do:
                addMiddleware(
                    `path`,
                    HttpMethod(`verb`),
                    HandlerType(`position`),
                    `ident`
                )
        result &= route.call
