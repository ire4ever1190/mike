import tables
import macros

proc getDoParameters(doProc: NimNode): Table[string, NimNode] {.compileTime.} =
    expectKind(nnkDo)
    echo doProc.treeRepr