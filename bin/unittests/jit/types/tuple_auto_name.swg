#global fileprivate

#test
{
    let x = 10
    let y = 20
    let t = {x, y}
    @assert(t.x == 10)
    @assert(t.y == 20)
}

#test
{
    let name = "Alice"
    let age = 30
    let t = {name, age}
    @assert(t.name == "Alice")
    @assert(t.age == 30)
}

#test
{
    let a = true
    let b = 3.14
    let t = {a, b}
    @assert(t.a == true)
    @assert(t.b == 3.14)
}

#test
{
    let x = 1
    let t = {x, y: 2}
    @assert(t.x == 1)
    @assert(t.y == 2)
}
