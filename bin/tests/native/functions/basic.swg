#global fileprivate // swc-option suite-test

var gBasicF0Calls: s32
var gBasicF1Last: s32
var gBasicACalls: s32
var gBasicBLast: s32
var gBasicCLast: s32
var gBasicDLast: s32
var gBasicF5Last: s32
var gBasicF6Last: s32
func A() { gBasicACalls += 1 }
func B(x: s32) { gBasicBLast = x }
func C(x: s32, y: s32) { gBasicCLast = x + y }
func D(x, y: s32 = 0) { gBasicDLast = x * 10 + y }


func T()->s32
{
    let a = T()
    return a
}

func T1(a0, b0: s32)->s32
{
    let c = a0
    return c
}

namespace NS {}

#test
{
    gBasicF0Calls = 0
    gBasicF1Last  = 0
    F0()
    F1(1)
    @assert(gBasicF0Calls == 1)
    @assert(gBasicF1Last == 1)
}

#test
{
    gBasicACalls = 0
    gBasicBLast  = 0
    gBasicCLast  = 0
    gBasicDLast  = 0
    gBasicF5Last = 0
    gBasicF6Last = 0
    A()
    B(10)
    C(1, 2)
    D(1)
    D(1, 2)
    F5(1)
    F5(1, 2)
    F6(1)
    F6(1, 2)
    @assert(gBasicACalls == 1)
    @assert(gBasicBLast == 10)
    @assert(gBasicCLast == 3)
    @assert(gBasicDLast == 12)
    @assert(gBasicF5Last == 12)
    @assert(gBasicF6Last == 12)
}



func F0() { gBasicF0Calls += 1 }
func F1(x: s32) { gBasicF1Last = x }



func F5(a: s32, b: s32 = 0) { gBasicF5Last = a * 10 + b }
func F6(a, b: s32 = 0) { gBasicF6Last = a * 10 + b }
