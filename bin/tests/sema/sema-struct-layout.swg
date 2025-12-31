#global internal

struct A
{
    a: u32
    b: u32
}

#assert(#sizeof(A) == 8)