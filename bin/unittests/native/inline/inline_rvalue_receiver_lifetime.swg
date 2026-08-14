#global private

// An inline method called on an RVALUE receiver returns a slice into the receiver's own
// storage, and the slice is consumed by the enclosing call. The receiver must stay alive
// until the whole statement finishes: homed by value into the inline expansion, the inline
// scope's exit would drop it while the slice is still in flight. opDrop poisons the payload
// so a premature drop is observable without any allocator involvement.
struct Text
{
    storage: [16] u8
    len:     u64
}

impl Text
{
    mtd opDrop()
    {
        for i in 16 do
            .storage[i] = 0
        .len = 0
    }

    #[Swag.Inline]
    mtd const view()->string
    {
        return @mkstring(&.storage[0], .len)
    }
}

func makeText()->Text
{
    var t: Text
    t.storage[0] = 'H'u8
    t.storage[1] = 'i'u8
    t.len        = 2
    return t
}

func firstByte(s: string)->u8
{
    if @countof(s) != 2 do
        return 0
    return s[0]
}

#test
{
    // Rvalue receiver: the slice must still see the receiver's bytes.
    @assert(firstByte(makeText().view()) == 'H'u8)
}

#test
{
    // Named receiver: the healthy control.
    let t = makeText()
    @assert(firstByte(t.view()) == 'H'u8)
}
