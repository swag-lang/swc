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

struct ReceiverConstMethodOverload
{
    mutableCalls: s32
}

impl ReceiverConstMethodOverload
{
    mtd select()->s32
    {
        .mutableCalls += 1
        return 1
    }

    mtd const select()->s32
    {
        return 2
    }
}

#test
{
    var value = ReceiverConstMethodOverload{}
    @assert(value.select() == 1)
    @assert(value.mutableCalls == 1)
}

#test
{
    let value = ReceiverConstMethodOverload{}
    @assert(value.select() == 2)
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

func preferFloatLiteral(x, y: f32)->f32 => x + y
func preferFloatLiteral(x, y: f64)->f64 => x + y
func(T) preferFloatLiteral(x, y: T)->T => y

#test
{
    let f32Value = preferFloatLiteral(0.0001, 1.0'f32)
    let f64Value = preferFloatLiteral(0.0001, 1.0'f64)

    #assert(#typeof(f32Value) == f32)
    #assert(#typeof(f64Value) == f64)
    @assert(f32Value > 1.0'f32)
    @assert(f64Value > 1.0'f64)
}
