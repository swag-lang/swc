#global private

var gVariadicAnyTotal:   u64
var gVariadicTypedTotal: u64
var gVariadicTotoCalls:  u64
var gVariadicTotoTotal:  u64
var gVariadicTotoHead:   s32
var gVariadicTutuCalls:  u64
var gVariadicTutuTotal:  u64
var gVariadicTutuHead:   s32
func titi(a: ...) { gVariadicAnyTotal += a.count }
func tata(a: s32...) { gVariadicTypedTotal += a.count }

#test
{
    gVariadicAnyTotal   = 0
    gVariadicTypedTotal = 0
    titi("a", "b")
    titi()
    tata(1, 2, 3)
    tata()
    Swag.assert(gVariadicAnyTotal == 2)
    Swag.assert(gVariadicTypedTotal == 3)
}

func toto(a: s32, b: ...)
{
    gVariadicTotoCalls += 1
    gVariadicTotoTotal += b.count
    gVariadicTotoHead  = a
}
#test
{
    gVariadicTotoCalls = 0
    gVariadicTotoTotal = 0
    gVariadicTotoHead  = 0
    toto(1, "a", "b")
    toto(1)
    Swag.assert(gVariadicTotoCalls == 2)
    Swag.assert(gVariadicTotoTotal == 2)
    Swag.assert(gVariadicTotoHead == 1)
}

func tutu(a: s32, b: s32...)
{
    gVariadicTutuCalls += 1
    gVariadicTutuTotal += b.count
    gVariadicTutuHead  = a
}
#test
{
    gVariadicTutuCalls = 0
    gVariadicTutuTotal = 0
    gVariadicTutuHead  = 0
    tutu(1)
    tutu(1, 2)
    tutu(1, 2, 3)
    Swag.assert(gVariadicTutuCalls == 3)
    Swag.assert(gVariadicTutuTotal == 3)
    Swag.assert(gVariadicTutuHead == 1)
}
