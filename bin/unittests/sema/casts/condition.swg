#global private

func semaTest001()
{
    var a: #null *s32
    if !a {}
    var b: #null string
    if !b {}
    var c: #null [..] s32
    if !c {}
    var d: #null [*] bool
    if !d {}
    var e: #null func()
    if !e {}
    var f: #null typeinfo
    if !f {}
}

func semaTest002()
{
    var a: #null *s32
    var b: #null *s32
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
    var a: #null *s32
    var b: #null *s32

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
    var a: #null *s32

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
    var s: #null string
    @assert(!s)

    s = "abc"
    @assert(!s == false)
}

func semaTest008()
{
    var a: [2] s32
    var s: [..] s32 = a
    @assert(!s == false)

    var n: #null [..] s32 = null
    @assert(!n)
}
