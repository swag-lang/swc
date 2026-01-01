#global internal

struct A
{
    a: u32
    b: u32
}

#assert(#sizeof(A) == 8)

struct B
{
    a: u32
#if false {
    b: u32
}
}

#assert(#sizeof(B) == 4)
#assert(#offsetof(B.a) == 0)
//#assert(#offsetof(B.b) == 4)