// swc-option suite-test

#global fileprivate

struct Pair
{
    x: s32
    y: s32
}

var GZero: s32
var GInt: s32 = 21
var GBool: bool = true
var GPair: Pair = {x: 7, y: 9}
var GArray: [3] s32 = [1, 2, 3]
var GText: string = "abc"

#test
{
    @assert(GZero == 0)
    @assert(GInt == 21)
    @assert(GBool)
    @assert(GPair.x == 7)
    @assert(GPair.y == 9)
    @assert(GArray[0] == 1)
    @assert(GArray[1] == 2)
    @assert(GArray[2] == 3)
    @assert(GText == "abc")

    GZero = 42
    GInt += 9
    GBool = false
    GPair.x = -5
    GPair.y = 33
    GArray[0] = 10
    GArray[1] = 20
    GArray[2] = 30
    GText = "xyz"

    @assert(GZero == 42)
    @assert(GInt == 30)
    @assert(!GBool)
    @assert(GPair.x == -5)
    @assert(GPair.y == 33)
    @assert(GArray[0] == 10)
    @assert(GArray[1] == 20)
    @assert(GArray[2] == 30)
    @assert(GText == "xyz")

    var pInt = &GInt
    dref pInt = 77
    @assert(GInt == 77)

    var pPair = &GPair
    dref pPair = {x: 100, y: 200}
    @assert(GPair.x == 100)
    @assert(GPair.y == 200)
}
