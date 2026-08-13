#global private

struct Nb
{
    buf: #null [*] u64
    len: u64
}

impl Nb
{
    mtd poke()
    {
        .len = 0
        if .buf do
            .buf[0] = 0
    }

    // The inline clone must keep the narrowing proof through the pointer receiver.
    #[Swag.Inline]
    mtd pokeInline()
    {
        .len = 0
        if .buf do
            .buf[0] = 0
    }
}

#test
{
    var storage: [4] u64
    var n: Nb
    n.buf = &storage[0]
    n.poke()
    @assert(storage[0] == 0)

    storage[0] = 7
    n.pokeInline()
    @assert(storage[0] == 0)
}
