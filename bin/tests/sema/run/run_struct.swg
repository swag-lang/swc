#global fileprivate

struct Vec2
{
    x: s32
    y: s32
}

struct Box2
{
    min: Vec2
    max: Vec2
}

struct Flags
{
    a: bool
    b: bool
}

struct Holder
{
    count: s32
    flags: Flags
}

struct PtrWrap
{
    value: *s32
}

#run
{
    var a: Swag.Context
    a.runtimeFlags = .FromCompiler
    @assert(a.runtimeFlags == .FromCompiler)
    var b = &a.runtimeFlags
    var c = dref b
    @assert(c == .FromCompiler)
}

#run
{
    var a: Vec2 = {x: 1, y: 2}
    @assert(a.x == 1)
    @assert(a.y == 2)
}

#run
{
    var a: Vec2 = {x: -9, y: 12}
    var b = a
    @assert(b.x == -9)
    @assert(b.y == 12)
}

#run
{
    var a: Vec2 = {x: 3, y: 4}
    var b: Vec2
    b = a
    @assert(b.x == 3)
    @assert(b.y == 4)
}

#run
{
    var a: Vec2 = {x: 10, y: 20}
    var p = &a
    dref p = {x: 30, y: 40}
    @assert(a.x == 30)
    @assert(a.y == 40)
}

#run
{
    var a: Vec2 = {x: 7, y: 8}
    var px = &a.x
    var py = &a.y
    dref px = 70
    dref py = 80
    @assert(a.x == 70)
    @assert(a.y == 80)
}

#run
{
    var b: Box2 = {min: {x: 1, y: 2}, max: {x: 3, y: 4}}
    @assert(b.min.x == 1)
    @assert(b.min.y == 2)
    @assert(b.max.x == 3)
    @assert(b.max.y == 4)
}

#run
{
    var b0: Box2 = {min: {x: 2, y: 5}, max: {x: 7, y: 9}}
    var b1: Box2 = {min: {x: 0, y: 0}, max: {x: 0, y: 0}}
    b1 = b0
    @assert(b1.min.x == 2)
    @assert(b1.min.y == 5)
    @assert(b1.max.x == 7)
    @assert(b1.max.y == 9)
}

#run
{
    var b: Box2 = {min: {x: 0, y: 0}, max: {x: 0, y: 0}}
    b.min = {x: 11, y: 22}
    b.max = {x: 33, y: 44}
    @assert(b.min.x == 11)
    @assert(b.min.y == 22)
    @assert(b.max.x == 33)
    @assert(b.max.y == 44)
}

#run
{
    var h: Holder = {count: 5, flags: {a: true, b: false}}
    @assert(h.count == 5)
    @assert(h.flags.a)
    @assert(!h.flags.b)
}

#run
{
    var h: Holder = {count: 10, flags: {a: false, b: false}}
    h.flags.a = true
    h.flags.b = true
    h.count = 12
    @assert(h.count == 12)
    @assert(h.flags.a)
    @assert(h.flags.b)
}

#run
{
    var h: Holder = {count: 1, flags: {a: false, b: true}}
    var ph = &h
    dref ph = {count: 9, flags: {a: true, b: false}}
    @assert(h.count == 9)
    @assert(h.flags.a)
    @assert(!h.flags.b)
}

#run
{
    var v = 123's32
    var wrap: PtrWrap = {value: &v}
    @assert(dref wrap.value == 123)
    dref wrap.value = 321
    @assert(v == 321)
}

#run
{
    var left: Vec2 = {x: 6, y: 9}
    var right: Vec2 = {x: 1, y: 2}
    var pleft = &left
    var pright = &right
    dref pleft = dref pright
    @assert(left.x == 1)
    @assert(left.y == 2)
    @assert(right.x == 1)
    @assert(right.y == 2)
}

#run
{
    var a: Flags = {a: false, b: false}
    var b: Flags = {a: true, b: true}
    a = b
    @assert(a.a)
    @assert(a.b)
}

#run
{
    func test(x: &Vec2)->*Vec2 { return &x; }
    var v: Vec2 = {x: 5, y: 10}
    var p = test(&v)
    //@assert(p.x == 5)
    //@assert(p.y == 10)
}