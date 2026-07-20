#global private

struct AA
{
    x: s32
    y: #null *BB
}

struct BB
{
    x: s32
    y: #null any
    z: #null *void
}

struct CC { a: #null *CC }
#assert(#sizeof(CC) == 8)

struct LL { p: #null *LLEnum }
enum LLEnum { LLEnum_A = #sizeof(LL) }

const NC: s32 = 42
enum NonCyclicEnum
{
    NCE_A = NC,
    NCE_B = NC + 1
}
#assert(NonCyclicEnum.NCE_A == 42)
#assert(NonCyclicEnum.NCE_B == 43)

#test
{
    struct AA
    {
        x: s32
    }

    var st: AA
    let x = st.x
    @assert(x == 0)
}

#test
{
    var a: AA
    var b: BB
    a.x = 1
    b.x = 2
    a.y = &b
    b.y = null
    b.z = null
    @assert(a.y.x == 2)
}

#test
{
    var c: CC
    c.a = &c
    @assert(c.a == &c)
}

#test
{
    var ll: LL
    ll.p = null
    @assert(ll.p == null)
}

#test
{
    var e: NonCyclicEnum = .NCE_B
    @assert(e == NonCyclicEnum.NCE_B)
}

struct Empty {}
const A0: Empty = {}
