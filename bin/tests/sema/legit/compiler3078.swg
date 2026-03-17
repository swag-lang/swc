#global fileprivate // swc-option sema-only
#global skip
// Multiple strings are compiled as one
const a = "this is " ++ "a" ++ " string"
#assert(a == "this is a string")
