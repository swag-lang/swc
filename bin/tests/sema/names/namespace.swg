#global fileprivate

namespace NA {}
namespace NA.NB.NC {}

namespace NA { const A = 52 }

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
