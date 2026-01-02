#global internal

const A = 0
#assert(#stringof(A) == "0")

enum Test{
    A = 1,
    B = 2,
    C = 3,
}

#assert(#fullnameof(Test.A) == "Test.A")
#assert(#nameof(Test.A) == "A")

#assert(#stringof(cast(u32) Test.A) == "1")
#assert(#stringof(5) == "5")
#assert(#stringof(5*5) == "25")
#assert(#stringof("hello") == "hello")
#assert(#stringof(bool) == "bool")