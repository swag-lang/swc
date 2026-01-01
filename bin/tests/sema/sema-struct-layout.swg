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
#assert(#offsetof(B.b) == 4) // swc-expected-error {{sema_err_unknown_symbol}}

#assert(#offsetof(A.a) == 0)
#assert(#offsetof(A.b) == 4)

#assert(#offsetof(A) == 4) // swc-expected-error {{sema_err_invalid_offsetof}}
#assert(#offsetof(5) == 4) // swc-expected-error {{sema_err_invalid_offsetof}}