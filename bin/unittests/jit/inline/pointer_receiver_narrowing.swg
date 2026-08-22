#global private

struct PointerReceiverNarrowing
{
    buffer: #null [*] u8
}

impl PointerReceiverNarrowing
{
    #[Swag.Inline]
    mtd clearFirst()
    {
        if .buffer do
            .buffer[0] = 0
    }
}

#test
{
    var storage = [7'u8]
    var value: PointerReceiverNarrowing
    value.buffer = &storage[0]
    value.clearFirst()
    @assert(storage[0] == 0)

}
