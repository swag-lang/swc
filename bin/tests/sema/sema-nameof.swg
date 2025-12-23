#global internal

const A = 0
#assert(#nameof(A) == "A")
#assert(#nameof(bool) == "bool")
#assert(#nameof(u32) == "u32")

enum Test{
    A = 1,
    B = 2,
    C = 3,
}

#assert(#nameof(Test.A) == "A")