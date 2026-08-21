#global private

func semaTest001()
{
    const P = cast(*void) 0x1234'u64
    const V = cast(u64) P
    #assert(#typeof(P) == *void)
    #assert(#typeof(V) == u64)
    #assert(V == 0x1234'u64)
    #assert(P == cast(*void) V)
}

func semaTest002()
{
    const P = cast([*]u8) 0xABCD'u64
    const V = cast(u64) P
    #assert(#typeof(P) == [*]u8)
    #assert(#typeof(V) == u64)
    #assert(V == 0xABCD'u64)
    #assert(P == cast([*]u8) V)
}

func semaTest003()
{
    const P0 = cast(*void) 0x1234'u64
    const P1 = cast(*void) 0x1235'u64
    #assert(P0 != P1)
    #assert(P0 == cast(*void) 0x1234'u64)
}

// Every integer that fits in an address converts to a pointer in one explicit cast,
// zero-extended when it is narrower than one.
enum PointerCastKind: u32 { First = 7, Second = 9 }
enum PointerCastHandle: u64 { First = 7, Second = 9 }

func semaTest004()
{
    const FROM_U32 = cast(*void) 0x1234'u32
    const FROM_U16 = cast(*void) 0xABCD'u16
    const FROM_U8  = cast(*void) 0x42'u8
    const FROM_S32 = cast(*void) 16's32
    const FROM_S64 = cast(*void) 16's64
    #assert(FROM_U32 == cast(*void) 0x1234'u64)
    #assert(FROM_U16 == cast(*void) 0xABCD'u64)
    #assert(FROM_U8 == cast(*void) 0x42'u64)
    #assert(FROM_S32 == FROM_S64)
}

func semaTest005()
{
    // An enum reaches a pointer through its underlying type, and comes back from one
    // whose width can hold an address.
    const FROM_ENUM = cast(*void) PointerCastKind.First
    const TO_ENUM   = cast(PointerCastHandle) cast(*void) 9'u64
    #assert(FROM_ENUM == cast(*void) 7'u64)
    #assert(TO_ENUM == PointerCastHandle.Second)
}

func semaTest006()
{
    // A pointer reads as any integer at least as wide as an address.
    const P = cast(*void) 0x1234'u64
    #assert(cast(s64) P == 0x1234's64)
    #assert(#typeof(cast(s64) P) == s64)
}
