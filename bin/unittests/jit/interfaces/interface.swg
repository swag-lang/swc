#global fileprivate

interface I1 { mtd toto(); }
struct T {}

var gInterfaceTitiCalls: s32
var gInterfaceImplTotoCalls: s32

impl T
{
    mtd toto(x: s32) {}
}

impl I1 for T
{
    mtd impl toto() { gInterfaceImplTotoCalls += 1 }
    func titi() { gInterfaceTitiCalls += 1 }
    mtd tata() { me.toto() }
    mtd tonton() { .toto() }
}

func runHelperFunc()->bool
{
    gInterfaceTitiCalls = 0
    T.I1.titi()
    return gInterfaceTitiCalls == 1
}

func runBasicCast()->bool
{
    var t: T
    var i = cast(I1) t
    gInterfaceImplTotoCalls = 0
    i.toto()
    return gInterfaceImplTotoCalls == 1
}

#test
{
    const ok0 = #run runHelperFunc()
    #assert(ok0)
}

#test
{
    const ok1 = #run runBasicCast()
    #assert(ok1)
}
