#global fileprivate // swc-option sema-only
#global skip
attr AA()

func toto(x: typeinfo) {}

//#assert(#stringof(toto) == "toto")
//#assert(#stringof(AA) == "AA")
