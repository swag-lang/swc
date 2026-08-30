#global private

// A global written by a '#run' block keeps its value into the emitted binary only when its
// storage is emitted verbatim. '= undefined' places the global in the initialized data
// segment, so what compile-time execution wrote is the byte image the artifact ships; a
// zero-initialized global would land in '.bss' and lose the write, which is now an error.
// Both halves of the language must agree here: this test runs under the JIT and again from
// the produced executable.
struct Pair
{
    x: s32
    y: s32
}

var GScalar: s32     = undefined
var GArray:  [3] s32 = undefined
var GPair:   Pair    = undefined
var GSeeded: s32     = 1

#run
{
    GScalar   = 7
    GArray[0] = 10
    GArray[1] = 20
    GArray[2] = 30
    GPair.x   = -5
    GPair.y   = 33
    GSeeded   = 9
}

#test
{
    Swag.assert(GScalar == 7)
    Swag.assert(GArray[0] == 10)
    Swag.assert(GArray[1] == 20)
    Swag.assert(GArray[2] == 30)
    Swag.assert(GPair.x == -5)
    Swag.assert(GPair.y == 33)
    Swag.assert(GSeeded == 9)
}
