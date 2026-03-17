#global fileprivate // swc-option sema-only
namespace A
{
    namespace B
    {
        alias tt1 = bool
    }
}

var a: A.B.tt1 = true
