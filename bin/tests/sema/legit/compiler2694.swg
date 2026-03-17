#global fileprivate // swc-option sema-only
#global skip
struct AA {}

func titi()
{
    var x:  AA
    var ptr = {&x}
}
