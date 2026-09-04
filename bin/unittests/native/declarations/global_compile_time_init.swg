#global private

// A global written by a '#run' block is promoted from '.bss' to initialized data automatically.
// The artifact therefore receives the bytes produced by compile-time execution without a
// source-level uninitialized initializer.
// Both halves of the language must agree here: this test runs under the JIT and again from
// the produced executable.
struct Pair
{
    x: s32
    y: s32
}

var GScalar: s32
var GArray:  [3] s32
var GPair:   Pair
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
