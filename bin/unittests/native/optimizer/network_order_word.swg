#global private

// A binary container can store an unaligned, big-endian word anywhere in a
// byte stream. The indexed reads have the same semantics as a dword swap.
#[Swag.NoInline]
#[Swag.Optimize(true)]
func readNetworkWord(bytes: const [*] u8, offset: u64)->u32
{
    return (cast(u32) bytes[offset] << 24) |
           (cast(u32) bytes[offset + 1] << 16) |
           (cast(u32) bytes[offset + 2] << 8) |
           cast(u32) bytes[offset + 3]
}

#test
{
    var bytes: [9] u8 = [0x00, 0x80, 0xFF, 0x01, 0x40, 0x12, 0x34, 0x56, 0x78]
    Swag.assert(readNetworkWord(&bytes[0], 0) == 0x0080FF01)
    Swag.assert(readNetworkWord(&bytes[0], 1) == 0x80FF0140)
    Swag.assert(readNetworkWord(&bytes[0], 5) == 0x12345678)
}
