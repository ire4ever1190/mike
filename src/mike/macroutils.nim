import tables
import macros

proc expectKind*(n: NimNode, k: NimNodeKind, msg: string) =
    if n.kind != k:
        error(msg, n)

# macro getParamTypeDesc*(prcIdent: typed, index: int): untyped =
#     ## Returns typedesc node for a proc at a certain index.
#     ## Index 0 contains the return type
#     # TODO, make this work on do syntax
#     let params = prcIdent.getTypeImpl().params
#     assert params.len >= index, "Proc doesn't have that many parameters"
#     result = params[index][1] # Index 1 contains the type
#
