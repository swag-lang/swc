#global private

#test
{
    let x = 10
    let y = 20
    let t = {x, y}
    Swag.require(t.x == 10)
    Swag.require(t.y == 20)
}

#test
{
    let name = "Alice"
    let age  = 30
    let t    = {name, age}
    Swag.require(t.name == "Alice")
    Swag.require(t.age == 30)
}

#test
{
    let a = true
    let b = 3.14
    let t = {a, b}
    Swag.require(t.a == true)
    Swag.require(t.b == 3.14)
}

#test
{
    let x = 1
    let t = {x, y: 2}
    Swag.require(t.x == 1)
    Swag.require(t.y == 2)
}
