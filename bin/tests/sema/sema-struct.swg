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
    a: DD
}