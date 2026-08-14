#global private

// Comparing a non-null pointer with 'null' is an identity question about the pointer,
// never a value question about the pointee: the relational retry peel must not route it
// to the pointee's 'opEquals' (whose overloads then reject the null operand).
struct Wnd
{
    x: s32
}

impl Wnd
{
    mtd const opEquals(other: Wnd)->bool
    {
        return .x == other.x
    }
}

func isAttached(parent: *Wnd)->bool
{
    return parent != null
}

func isDetached(parent: *Wnd)->bool
{
    return parent == null
}

#test
{
    var w: Wnd
    w.x = 3
    @assert(isAttached(&w))
    @assert(!isDetached(&w))

    // The pointee's opEquals still answers value questions.
    var o: Wnd
    o.x = 3
    @assert(w == o)
    o.x = 4
    @assert(!(w == o))
}
