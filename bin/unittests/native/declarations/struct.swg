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
    var a: Vec2 = {x: 1, y: 2}
    Swag.assert(a.x == 1)
    Swag.assert(a.y == 2)
}

#test
{
    var a: Vec2 = {x: -9, y: 12}
    var b       = a
    Swag.assert(b.x == -9)
    Swag.assert(b.y == 12)
}

#test
{
    var a: Vec2 = {x: 3, y: 4}
    var b: Vec2
    b = a
    Swag.assert(b.x == 3)
    Swag.assert(b.y == 4)
}

#test
{
    var a: Vec2 = {x: 10, y: 20}
    var p       = &a
    p[] = {x: 30, y: 40}
    Swag.assert(a.x == 30)
    Swag.assert(a.y == 40)
}

#test
{
    var a: Vec2 = {x: 7, y: 8}
    var px      = &a.x
    var py      = &a.y
    px[] = 70
    py[] = 80
    Swag.assert(a.x == 70)
    Swag.assert(a.y == 80)
}

#test
{
    var b: Box2 = {min: {x: 1, y: 2}, max: {x: 3, y: 4}}
    Swag.assert(b.min.x == 1)
    Swag.assert(b.min.y == 2)
    Swag.assert(b.max.x == 3)
    Swag.assert(b.max.y == 4)
}

#test
{
    var b0: Box2 = {min: {x: 2, y: 5}, max: {x: 7, y: 9}}
    var b1: Box2 = {min: {x: 0, y: 0}, max: {x: 0, y: 0}}
    b1 = b0
    Swag.assert(b1.min.x == 2)
    Swag.assert(b1.min.y == 5)
    Swag.assert(b1.max.x == 7)
    Swag.assert(b1.max.y == 9)
}

#test
{
    var b: Box2 = {min: {x: 0, y: 0}, max: {x: 0, y: 0}}
    b.min = {x: 11, y: 22}
    b.max = {x: 33, y: 44}
    Swag.assert(b.min.x == 11)
    Swag.assert(b.min.y == 22)
    Swag.assert(b.max.x == 33)
    Swag.assert(b.max.y == 44)
}

#test
{
    var h: Holder = {count: 5, flags: {a: true, b: false}}
    Swag.assert(h.count == 5)
    Swag.assert(h.flags.a)
    Swag.assert(!h.flags.b)
}

#test
{
    var h: Holder = {count: 10, flags: {a: false, b: false}}
    h.flags.a = true
    h.flags.b = true
    h.count   = 12
    Swag.assert(h.count == 12)
    Swag.assert(h.flags.a)
    Swag.assert(h.flags.b)
}

#test
{
    var h: Holder = {count: 1, flags: {a: false, b: true}}
    var ph        = &h
    ph[] = {count: 9, flags: {a: true, b: false}}
    Swag.assert(h.count == 9)
    Swag.assert(h.flags.a)
    Swag.assert(!h.flags.b)
}

#test
{
    var v             = 123's32
    var wrap: PtrWrap = {value: &v}
    Swag.assert(wrap.value[] == 123)
    wrap.value[] = 321
    Swag.assert(v == 321)
}

#test
{
    var left:  Vec2 = {x: 6, y: 9}
    var right: Vec2 = {x: 1, y: 2}
    var pleft       = &left
    var pright      = &right
    pleft[] = pright[]
    Swag.assert(left.x == 1)
    Swag.assert(left.y == 2)
    Swag.assert(right.x == 1)
    Swag.assert(right.y == 2)
}

#test
{
    var a: Flags = {a: false, b: false}
    var b: Flags = {a: true, b: true}
    a = b
    Swag.assert(a.a)
    Swag.assert(a.b)
}

#test
{
    func test(x: *Vec2)->*Vec2 { return x; }
    var v: Vec2 = {x: 5, y: 10}
    var p       = test(&v)
    Swag.assert(p.x == 5)
    Swag.assert(p.y == 10)
}
