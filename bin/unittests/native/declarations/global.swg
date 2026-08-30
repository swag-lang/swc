// 

#global private

struct Pair
{
    x: s32
    y: s32
}

var GZero:  s32
var GInt:   s32     = 21
var GBool:  bool    = true
var GPair:  Pair    = {x: 7, y: 9}
var GArray: [3] s32 = [1, 2, 3]
var GText:  string  = "abc"

#test
{
    Swag.assert(GZero == 0)
    Swag.assert(GInt == 21)
    Swag.assert(GBool)
    Swag.assert(GPair.x == 7)
    Swag.assert(GPair.y == 9)
    Swag.assert(GArray[0] == 1)
    Swag.assert(GArray[1] == 2)
    Swag.assert(GArray[2] == 3)
    Swag.assert(GText == "abc")

    GZero     = 42
    GInt      += 9
    GBool     = false
    GPair.x   = -5
    GPair.y   = 33
    GArray[0] = 10
    GArray[1] = 20
    GArray[2] = 30
    GText     = "xyz"

    Swag.assert(GZero == 42)
    Swag.assert(GInt == 30)
    Swag.assert(!GBool)
    Swag.assert(GPair.x == -5)
    Swag.assert(GPair.y == 33)
    Swag.assert(GArray[0] == 10)
    Swag.assert(GArray[1] == 20)
    Swag.assert(GArray[2] == 30)
    Swag.assert(GText == "xyz")

    var pInt = &GInt
    pInt[] = 77
    Swag.assert(GInt == 77)

    var pPair = &GPair
    pPair[] = {x: 100, y: 200}
    Swag.assert(GPair.x == 100)
    Swag.assert(GPair.y == 200)
}
