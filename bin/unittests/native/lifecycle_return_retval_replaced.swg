// A function that names its result with 'retval' and returns another value replaces what that
// variable holds. The other value is built apart from the result storage, even when it still
// reads the variable through a pointer, and the replaced value is released exactly once.

var ReplacedLive: s32
var ReplacedSeed: s32 = 1

// Inline storage, like a short string: building over it clears what the argument reads.
struct ReplacedText
{
    buf: [16] u8
    len: u64
}

impl ReplacedText
{
    #[Swag.NoInline]
    mtd const view()->const [..] u8 => buf[0 until len]
}

// Writes its result before reading the argument, like a conversion constructor.
#[Swag.NoInline]
func replacedText(src: const [..] u8)->ReplacedText
{
    var r: retval
    for i in src.count do
        r.buf[i] = src[i]
    r.len = src.count
    return r
}

#[Swag.NoInline]
func trimThroughPointer()->ReplacedText
{
    var result: retval = replacedText(" Satie ")
    let p = &result
    return replacedText(p.view()[1 until 6])
}

#[Swag.Inline]
func trimInlined()->ReplacedText
{
    var result: retval = replacedText(" Satie ")
    let p = &result
    return replacedText(p.view()[1 until 6])
}

#[Swag.NoInline]
func callTrimInlined()->ReplacedText => trimInlined()

// Counts its live values, like a string owning a heap buffer.
struct ReplacedOwner
{
    id:  s64
    pad: [4] u64
}

impl ReplacedOwner
{
    mtd opDrop()
    {
        ReplacedLive -= 1
    }
}

#[Swag.NoInline]
func replacedOwner(id: s64)->ReplacedOwner
{
    ReplacedLive += 1
    var r: retval
    r.id = id
    return r
}

#[Swag.NoInline]
func ownerReplaced(other: bool)->ReplacedOwner
{
    var result: retval = replacedOwner(1)
    if other do
        return replacedOwner(2)
    return result
}

#[Swag.Inline]
func ownerReplacedInlined(other: bool)->ReplacedOwner
{
    var result: retval = replacedOwner(1)
    if other do
        return replacedOwner(2)
    return result
}

#[Swag.NoInline]
func callOwnerReplacedInlined(other: bool)->ReplacedOwner => ownerReplacedInlined(other)

// Returning the variable through a pointer neither releases nor copies it.
#[Swag.NoInline]
func ownerThroughPointer()->ReplacedOwner
{
    var result: retval = replacedOwner(3)
    let p = &result
    return p[]
}

// Fits a register: the variable is not the result storage, and is released with the locals.
struct ReplacedTiny
{
    id: s32
}

impl ReplacedTiny
{
    mtd opDrop()
    {
        ReplacedLive -= 1
    }
}

#[Swag.NoInline]
func replacedTiny(id: s32)->ReplacedTiny
{
    ReplacedLive += 1
    return {id: id}
}

#[Swag.NoInline]
func tinyReplaced(other: bool)->ReplacedTiny
{
    var result: retval = replacedTiny(1)
    if other do
        return replacedTiny(2)
    return result
}

#test
{
    scope
    {
        let a = trimThroughPointer()
        Swag.assert(a.len == 5 and a.buf[0] == 83 and a.buf[4] == 101)
        let b = callTrimInlined()
        Swag.assert(b.len == 5 and b.buf[0] == 83 and b.buf[4] == 101)
    }

    // A runtime condition keeps the calls out of compile-time evaluation.
    let other = ReplacedSeed > 0
    ReplacedLive = 0
    scope
    {
        let a = ownerReplaced(other)
        let b = ownerReplaced(not other)
        Swag.assert(a.id == 2 and b.id == 1)
    }
    Swag.assert(ReplacedLive == 0)

    scope
    {
        let a = callOwnerReplacedInlined(other)
        let b = callOwnerReplacedInlined(not other)
        Swag.assert(a.id == 2 and b.id == 1)
    }
    Swag.assert(ReplacedLive == 0)

    scope
    {
        let a = ownerThroughPointer()
        Swag.assert(a.id == 3)
    }
    Swag.assert(ReplacedLive == 0)

    scope
    {
        let a = tinyReplaced(other)
        let b = tinyReplaced(not other)
        Swag.assert(a.id == 2 and b.id == 1)
    }
    Swag.assert(ReplacedLive == 0)
}
