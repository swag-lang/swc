// 

#global private

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

#test
{
    var a: Vec2 = Vec2{x: 1, y: 2}
    Swag.require(a.x == 1)
    Swag.require(a.y == 2)
}

#test
{
    var a: Vec2 = Vec2{x: -9, y: 12}
    var b       = a
    Swag.require(b.x == -9)
    Swag.require(b.y == 12)
}

#test
{
    var a: Vec2 = Vec2{x: 3, y: 4}
    var b: Vec2
    b = a
    Swag.require(b.x == 3)
    Swag.require(b.y == 4)
}

#test
{
    var a: Vec2 = Vec2{x: 10, y: 20}
    var p       = &a
    p[] = {x: 30, y: 40}
    Swag.require(a.x == 30)
    Swag.require(a.y == 40)
}

#test
{
    var a: Vec2 = Vec2{x: 7, y: 8}
    var px      = &a.x
    var py      = &a.y
    px[] = 70
    py[] = 80
    Swag.require(a.x == 70)
    Swag.require(a.y == 80)
}

#test
{
    var b: Box2 = Box2{min: Vec2{x: 1, y: 2}, max: Vec2{x: 3, y: 4}}
    Swag.require(b.min.x == 1)
    Swag.require(b.min.y == 2)
    Swag.require(b.max.x == 3)
    Swag.require(b.max.y == 4)
}

#test
{
    var b0: Box2 = Box2{min: Vec2{x: 2, y: 5}, max: Vec2{x: 7, y: 9}}
    var b1: Box2 = Box2{min: Vec2{x: 0, y: 0}, max: Vec2{x: 0, y: 0}}
    b1 = b0
    Swag.require(b1.min.x == 2)
    Swag.require(b1.min.y == 5)
    Swag.require(b1.max.x == 7)
    Swag.require(b1.max.y == 9)
}

#test
{
    var b: Box2 = Box2{min: Vec2{x: 0, y: 0}, max: Vec2{x: 0, y: 0}}
    b.min = {x: 11, y: 22}
    b.max = {x: 33, y: 44}
    Swag.require(b.min.x == 11)
    Swag.require(b.min.y == 22)
    Swag.require(b.max.x == 33)
    Swag.require(b.max.y == 44)
}

#test
{
    var h: Holder = Holder{count: 5, flags: Flags{a: true, b: false}}
    Swag.require(h.count == 5)
    Swag.require(h.flags.a)
    Swag.require(not h.flags.b)
}

#test
{
    var h: Holder = Holder{count: 10, flags: Flags{a: false, b: false}}
    h.flags.a = true
    h.flags.b = true
    h.count   = 12
    Swag.require(h.count == 12)
    Swag.require(h.flags.a)
    Swag.require(h.flags.b)
}

#test
{
    var h: Holder = Holder{count: 1, flags: Flags{a: false, b: true}}
    var ph        = &h
    ph[] = {count: 9, flags: {a: true, b: false}}
    Swag.require(h.count == 9)
    Swag.require(h.flags.a)
    Swag.require(not h.flags.b)
}

#test
{
    var v = 123's32
    var wrap: PtrWrap = PtrWrap{value: &v}
    Swag.require(wrap.value[] == 123)
    wrap.value[] = 321
    Swag.require(v == 321)
}

#test
{
    var left:  Vec2 = Vec2{x: 6, y: 9}
    var right: Vec2 = Vec2{x: 1, y: 2}
    var pleft       = &left
    var pright      = &right
    pleft[] = pright[]
    Swag.require(left.x == 1)
    Swag.require(left.y == 2)
    Swag.require(right.x == 1)
    Swag.require(right.y == 2)
}

#test
{
    var a: Flags = Flags{a: false, b: false}
    var b: Flags = Flags{a: true, b: true}
    a = b
    Swag.require(a.a)
    Swag.require(a.b)
}

#test
{
    func test(x: *Vec2)->*Vec2 { return x; }
    var v: Vec2 = Vec2{x: 5, y: 10}
    var p       = test(&v)
    Swag.require(p.x == 5)
    Swag.require(p.y == 10)
}
