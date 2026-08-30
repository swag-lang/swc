#global private

#test
{
    func square(x: s32) => x * x
    alias sq = square
    Swag.assert(sq(5) == 25)
}

#test
{
    func add(a: s32, b: s32) => a + b
    alias plus = add
    Swag.assert(plus(3, 7) == 10)
}

#test
{
    func greet()->string { return "hello" }
    alias hi = greet
    Swag.assert(hi() == "hello")
}

#test
{
    var myLongName: s32 = 0
    alias short = myLongName
    short += 5
    Swag.assert(myLongName == 5)
    short = 10
    Swag.assert(myLongName == 10)
}

#test
{
    var a: s32 = 1
    var b: s32 = 2
    alias x = a
    alias y = b
    x += y
    Swag.assert(a == 3)
    Swag.assert(b == 2)
}
