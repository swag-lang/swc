#global fileprivate

func semaTest001()
{
    var a: *s32
    if !a {}
    var b: string
    if !b {}
    var c: [..] s32
    if !c {}
    var d: [*] bool
    if !d {}
    var e: func()
    if !e {}
    var f: typeinfo
    if !f {}
}

func semaTest002()
{
    var a: *s32
    var b: *s32
    if !a or !b {}
}

const A = ""

func semaTest003()
{
    var a: s32
    if a and a {}
}

func semaTest004()
{
    var a: *s32
    var b: *s32

    @assert(!a or !b)

    var ax: s32
    a = &ax
    @assert(!a or !b)

    var bx: s32
    b = &bx
    @assert((!a or !b) == false)
}

func semaTest005()
{
    var a: s32

    @assert((a and a) == false)
    @assert(a or !a)
    @assert((a or a) == false)

    a = 1
    @assert(a and a)
    @assert(a or !a)
    @assert(a or a)
}

func semaTest006()
{
    var a: *s32

    @assert((a and a) == false)
    @assert(a or !a)
    @assert((a or a) == false)

    var ax: s32
    a = &ax
    @assert(a and a)
    @assert(a or !a)
    @assert(a or a)
}

func semaTest007()
{
    var s: string
    @assert(!s)

    s = "abc"
    @assert(!s == false)
}

func semaTest008()
{
    var a: [2] s32
    var s: [..] s32 = a
    @assert(!s == false)

    var n: [..] s32 = null
    @assert(!n)
}
