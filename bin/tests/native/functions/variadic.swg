#global fileprivate // 

var gVariadicAnyTotal: u64
var gVariadicTypedTotal: u64
var gVariadicTotoCalls: u64
var gVariadicTotoTotal: u64
var gVariadicTotoHead: s32
var gVariadicTutuCalls: u64
var gVariadicTutuTotal: u64
var gVariadicTutuHead: s32
func titi(a: ...) { gVariadicAnyTotal += @countof(a) }
func tata(a: s32...) { gVariadicTypedTotal += @countof(a) }

#test
{
    gVariadicAnyTotal   = 0
    gVariadicTypedTotal = 0
    titi("a", "b")
    titi()
    tata(1, 2, 3)
    tata()
    @assert(gVariadicAnyTotal == 2)
    @assert(gVariadicTypedTotal == 3)
}

func toto(a: s32, b: ...)
{
    gVariadicTotoCalls += 1
    gVariadicTotoTotal += @countof(b)
    gVariadicTotoHead = a
}
#test
{
    gVariadicTotoCalls = 0
    gVariadicTotoTotal = 0
    gVariadicTotoHead  = 0
    toto(1, "a", "b")
    toto(1)
    @assert(gVariadicTotoCalls == 2)
    @assert(gVariadicTotoTotal == 2)
    @assert(gVariadicTotoHead == 1)
}

func tutu(a: s32, b: s32...)
{
    gVariadicTutuCalls += 1
    gVariadicTutuTotal += @countof(b)
    gVariadicTutuHead = a
}
#test
{
    gVariadicTutuCalls = 0
    gVariadicTutuTotal = 0
    gVariadicTutuHead  = 0
    tutu(1)
    tutu(1, 2)
    tutu(1, 2, 3)
    @assert(gVariadicTutuCalls == 3)
    @assert(gVariadicTutuTotal == 3)
    @assert(gVariadicTutuHead == 1)
}

