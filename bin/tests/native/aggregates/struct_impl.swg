#global fileprivate

// Struct with impl: methods, chaining via pointer return, multiple impl blocks.

struct Vec2
{
    x: s32
    y: s32
}

impl Vec2
{
    mtd length2()->s32 => .x * .x + .y * .y

    mtd add(other: const &Vec2)->Vec2
    {
        return {x: .x + other.x, y: .y + other.y}
    }

    mtd scale(factor: s32)->Vec2
    {
        return {x: .x * factor, y: .y * factor}
    }

    mtd isZero()->bool => .x == 0 and .y == 0
}

// Basic method calls.
#test
{
    var v: Vec2 = {x: 3, y: 4}
    @assert(v.length2() == 25)
    @assert(!v.isZero())

    var z: Vec2 = {x: 0, y: 0}
    @assert(z.isZero())
}

// Method returning new struct, chained.
#test
{
    var a: Vec2 = {x: 1, y: 2}
    var b: Vec2 = {x: 3, y: 4}
    let result = a.add(b).scale(2)
    @assert(result.x == 8)
    @assert(result.y == 12)
}

// Mutating method via pointer.
impl Vec2
{
    mtd negate()
    {
        .x = -.x
        .y = -.y
    }

    mtd addInPlace(other: const &Vec2)
    {
        .x += other.x
        .y += other.y
    }
}

#test
{
    var v: Vec2 = {x: 5, y: -3}
    v.negate()
    @assert(v.x == -5)
    @assert(v.y == 3)
}

#test
{
    var a: Vec2 = {x: 10, y: 20}
    var b: Vec2 = {x: 1, y: 2}
    a.addInPlace(b)
    a.addInPlace(b)
    @assert(a.x == 12)
    @assert(a.y == 24)
}

// Struct with nested struct and methods accessing nested fields.
struct Circle
{
    center: Vec2
    radius: s32
}

impl Circle
{
    mtd area100()->s32
    {
        // Approximate pi*r^2 * 100 as 314*r^2
        return 314 * .radius * .radius
    }

    mtd translate(dx: s32, dy: s32)
    {
        .center.x += dx
        .center.y += dy
    }
}

#test
{
    var c: Circle = {center: {x: 0, y: 0}, radius: 10}
    @assert(c.area100() == 31400)
    c.translate(5, 7)
    @assert(c.center.x == 5)
    @assert(c.center.y == 7)
}

// Method on struct with pointer field.
struct ListNode
{
    value: s32
    next: *ListNode
}

impl ListNode
{
    mtd count()->s32
    {
        var n = 1
        var cur = .next
        while cur != null
        {
            n += 1
            cur = cur.next
        }
        return n
    }
}

#test
{
    var c: ListNode = {value: 3, next: null}
    var b: ListNode = {value: 2, next: &c}
    var a: ListNode = {value: 1, next: &b}
    @assert(a.count() == 3)
    @assert(b.count() == 2)
    @assert(c.count() == 1)
}
