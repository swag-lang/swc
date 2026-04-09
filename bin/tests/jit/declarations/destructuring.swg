#global fileprivate

struct DestructPair
{
    x: s32
    y: s32
}

#test
{
    let pair = DestructPair{x: 10, y: 20}
    let (a, b) = pair
    @assert(a == 10)
    @assert(b == 20)
}

#test
{
    var pair = DestructPair{x: 10, y: 20}
    var (a, b) = pair
    @assert(a == 10)
    @assert(b == 20)
    a = 100
    b = 200
    @assert(a == 100)
    @assert(b == 200)
}

#test
{
    let (a, b) = {x: 1, y: 2}
    @assert(a == 1)
    @assert(b == 2)
}

#test
{
    var (a, b) = {x: 1, y: 2}
    @assert(a == 1)
    @assert(b == 2)
    a = 10
    b = 20
    @assert(a == 10)
    @assert(b == 20)
}

#test
{
    let (a, b, c) = {x: true, y: 42's32, z: 3.14}
    @assert(a == true)
    @assert(b == 42)
    @assert(c == 3.14)
}

#test
{
    var (a, b) = {x: true, y: false}
    @assert(a == true)
    @assert(b == false)
    a = false
    @assert(a == false)
}

#test
{
    let t = {x: 1.0, y: 2.0, z: 3.0}
    let (a, ?) = {x: 10, y: 20}
    @assert(a == 10)
    let (?, b) = {x: 10, y: 20}
    @assert(b == 20)
}

#test
{
    let t = {a: 1's32, b: 2's32, c: 3's32}
    let (?, ?, c) = t
    @assert(c == 3)
    let (x, ?, ?) = t
    @assert(x == 1)
    let (?, y, ?) = t
    @assert(y == 2)
}
