#global private

#test
{
    let x = 10
    let y = 20
    let t = {x, y}
    Swag.assert(t.x == 10)
    Swag.assert(t.y == 20)
}

#test
{
    let name = "Alice"
    let age  = 30
    let t    = {name, age}
    Swag.assert(t.name == "Alice")
    Swag.assert(t.age == 30)
}

#test
{
    let a = true
    let b = 3.14
    let t = {a, b}
    Swag.assert(t.a == true)
    Swag.assert(t.b == 3.14)
}

#test
{
    let x = 1
    let t = {x, y: 2}
    Swag.assert(t.x == 1)
    Swag.assert(t.y == 2)
}
