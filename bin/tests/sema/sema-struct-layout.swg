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

// Simple padding test: u8 + u32 + u8
struct C
{
    a: u8
    b: u32
    c: u8
}

#assert(#offsetof(C.a) == 0)
#assert(#offsetof(C.b) == 4) // 3 bytes of padding after a
#assert(#offsetof(C.c) == 8)
#assert(#sizeof(C) == 12)   // padded to multiple of 4

// Tail padding test: u32 + u8 + u8
struct D
{
    a: u32
    b: u8
    c: u8
}

#assert(#offsetof(D.a) == 0)
#assert(#offsetof(D.b) == 4)
#assert(#offsetof(D.c) == 5)
#assert(#sizeof(D) == 8)    // tail padding to alignment of 4


// Nested-struct layout
struct Inner
{
    x: u32
    y: u32
}

struct Outer
{
    a: u32
    b: Inner
    c: u32
}

#assert(#sizeof(Inner) == 8)
#assert(#offsetof(Inner.x) == 0)
#assert(#offsetof(Inner.y) == 4)

#assert(#offsetof(Outer.a) == 0)
#assert(#offsetof(Outer.b) == 4)
#assert(#offsetof(Outer.c) == 12)
#assert(#sizeof(Outer) == 16)


// offsetof on a non-existent field
struct E
{
    a: u32
}

#assert(#offsetof(E.a) == 0)
#assert(#offsetof(E.b) == 4) // swc-expected-error {{sema_err_unknown_symbol}}


// Conditional field in the middle of a struct
struct F
{
    a: u32
#if false {
    mid: u32
}
    b: u32
}

#assert(#offsetof(F.a) == 0)
#assert(#offsetof(F.b) == 4)
#assert(#sizeof(F) == 8)
#assert(#offsetof(F.mid) == 4) // swc-expected-error {{sema_err_unknown_symbol}}