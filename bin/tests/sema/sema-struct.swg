#global internal

struct AA
{
    x: s32
    y: *BB
}

struct BB
{
    x: s32
    y: any
    z: *void
}

struct CC
{
    a: *CC
}
#assert(#sizeof(CC) == 8)

struct DD
{
    a: DD // swc-expected-error {{sema_err_struct_circular_reference}}
}
/*
struct EE
{
    a: FF
}
struct FF
{
    a: EE
}
*/