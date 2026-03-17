#global fileprivate // swc-option sema-only
#global skip
//#global testerror "Err0091"

namespace A.B
{
    using A.C
}

namespace A.B
{
    func toto1() => toto()
}

namespace A.C
{
    func toto() {}
}
