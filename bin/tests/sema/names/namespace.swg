#global internal

namespace NA {}
namespace NA.NB.NC {}

namespace NA { const A = 52 }

// swc-expected-error@(+1,+2) {{sema_err_already_defined}}
namespace NB { const A = 0; }
namespace NB.A {}

const B = NA.A
#assert(B == 52)

namespace NC { enum MyEnum { X = 42 } }
const C = NC.MyEnum.X
#assert(C == 42)

namespace NE
{
    const E1 = 10
    const E2 = 20
}
#assert(NE.E1 == 10)
#assert(NE.E2 == 20)

namespace NF
{
    const X = 100
    namespace NF_Inner
    {
        const Y = 200
    }
}
#assert(NF.X == 100)
#assert(NF.NF_Inner.Y == 200)

namespace NG { const VAL = 'A' }
#assert(cast(rune) NG.VAL == 'A')

namespace NH
{
    const AAA = 5
    const BBB = 10
    const CCC = AAA + BBB
}

#assert(NH.AAA == 5)
#assert(NH.BBB == 10)
#assert(NH.CCC == 15)

#assert(NH == 1) // swc-expected-error {{sema_err_not_value_expr}}
#assert(NH + 1) // swc-expected-error {{sema_err_not_value_expr}}
#assert(-NH) // swc-expected-error {{sema_err_not_value_expr}}
#assert(cast(bool) NH) // swc-expected-error {{sema_err_not_value_expr}}

namespace Swag {} // swc-expected-error {{sema_err_reserved_swag_ns}}
namespace swag {} // swc-expected-error {{sema_err_reserved_swag_ns}}
namespace SWG.SWAG {} // swc-expected-error {{sema_err_reserved_swag_ns}}
