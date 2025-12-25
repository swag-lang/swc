#global internal

const A = 0
#assert(#stringof(A) == "A")

enum Test{
    A = 1,
    B = 2,
    C = 3,
}

#assert(#stringof(Test.A) == "Test.A")
#assert(#stringof(cast(u32) Test.A) == "1")
#assert(#stringof(5) == "5")
#assert(#stringof("hello") == "hello")
#assert(#stringof(bool) == "bool")