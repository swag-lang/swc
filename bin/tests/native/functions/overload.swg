#global fileprivate // 

var gOverloadA0Calls: s32
var gOverloadA1Last: s32
func A() { gOverloadA0Calls += 1 }
func A(a: s32) { gOverloadA1Last = a }

#test
{
    gOverloadA0Calls = 0
    gOverloadA1Last  = 0
    A()
    A(10)
    @assert(gOverloadA0Calls == 1)
    @assert(gOverloadA1Last == 10)
}


struct S {}
var gOverloadFoo0Calls: s32
var gOverloadFoo1Last: s32
impl S
{
    mtd foo() { gOverloadFoo0Calls += 1 }
    mtd foo(a: s32) { gOverloadFoo1Last = a }
}
#test
{
    var s: S
    gOverloadFoo0Calls = 0
    gOverloadFoo1Last  = 0
    s.foo()
    s.foo(10)
    @assert(gOverloadFoo0Calls == 1)
    @assert(gOverloadFoo1Last == 10)
}

#test
{
    var s: S
    gOverloadFoo0Calls = 0
    gOverloadFoo1Last  = 0
    S.foo(&s)
    S.foo(&s, 10)
    @assert(gOverloadFoo0Calls == 1)
    @assert(gOverloadFoo1Last == 10)
}


