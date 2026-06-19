#global fileprivate

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

struct CC { a: *CC }
#assert(#sizeof(CC) == 8)

struct LL { p: *LLEnum }
enum LLEnum { LLEnum_A = #sizeof(LL) }

const NC: s32 = 42
enum NonCyclicEnum
{
    NCE_A = NC,
    NCE_B = NC + 1
}
#assert(NonCyclicEnum.NCE_A == 42)
#assert(NonCyclicEnum.NCE_B == 43)

func semaTest001()
{
    struct AA
    {
        x: s32
    }

    var st: AA
    let x = st.x
}

func semaTest002()
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

func semaTest003()
{
    var c: CC
    c.a = &c
    @assert(c.a == &c)
}

func semaTest004()
{
    var ll: LL
    ll.p = null
    @assert(ll.p == null)
}

func semaTest005()
{
    var e: NonCyclicEnum = .NCE_B
    @assert(e == NonCyclicEnum.NCE_B)
}

struct Empty {}
const A0: Empty = {}
