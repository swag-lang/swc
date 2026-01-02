#global internal

const A = 0
#assert(#stringof(A) == "0")

enum Test{
    A = 1,
    B = 2,
    C = 3,
}

#assert(#fullnameof(Test.A) == "Test.A")
#assert(#fullnameof(Test.B) == "Test.B")
#assert(#fullnameof(Test.C) == "Test.C")

#assert(#nameof(Test.A) == "A")
#assert(#nameof(Test.B) == "B")
#assert(#nameof(Test.C) == "C")

#assert(#stringof(cast(u32) Test.A) == "1")
#assert(#stringof(cast(u32) Test.B) == "2")
#assert(#stringof(cast(u32) Test.C) == "3")

#assert(#stringof(5) == "5")
#assert(#stringof(5*5) == "25")
#assert(#stringof(1 + 2 * 3) == "7")

#assert(#stringof("hello") == "hello")
#assert(#stringof("foo" ++ "bar") == "foobar")

#assert(#stringof(bool) == "bool")
#assert(#stringof(Test) == "Test")

var S: string = "Swag"
#assert(#stringof(S) == "S")

const B = 2 + 3
#assert(#stringof(B) == "5")

const NEG = -10
#assert(#stringof(NEG) == "-10")

#assert(#stringof(true) == "true")
#assert(#stringof(false) == "false")

var X: s32 = 42
#assert(#stringof(X) == "X")
