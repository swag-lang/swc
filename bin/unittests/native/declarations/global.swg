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
var GPair:  Pair    = Pair{x: 7, y: 9}
var GArray: [3] s32 = [1, 2, 3]
var GText:  string  = "abc"

#test
{
    Swag.require(GZero == 0)
    Swag.require(GInt == 21)
    Swag.require(GBool)
    Swag.require(GPair.x == 7)
    Swag.require(GPair.y == 9)
    Swag.require(GArray[0] == 1)
    Swag.require(GArray[1] == 2)
    Swag.require(GArray[2] == 3)
    Swag.require(GText == "abc")

    GZero     = 42
    GInt      += 9
    GBool     = false
    GPair.x   = -5
    GPair.y   = 33
    GArray[0] = 10
    GArray[1] = 20
    GArray[2] = 30
    GText     = "xyz"

    Swag.require(GZero == 42)
    Swag.require(GInt == 30)
    Swag.require(not GBool)
    Swag.require(GPair.x == -5)
    Swag.require(GPair.y == 33)
    Swag.require(GArray[0] == 10)
    Swag.require(GArray[1] == 20)
    Swag.require(GArray[2] == 30)
    Swag.require(GText == "xyz")

    var pInt = &GInt
    pInt[] = 77
    Swag.require(GInt == 77)

    var pPair = &GPair
    pPair[] = {x: 100, y: 200}
    Swag.require(GPair.x == 100)
    Swag.require(GPair.y == 200)
}
