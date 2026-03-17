#global fileprivate // swc-option sema-only
#global skip
alias LARGE_INTEGER = s64
func toto(ptr: *LARGE_INTEGER) {}

func titi()
{
    var x: s64 = 0
    toto(&x)
}
