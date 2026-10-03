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

struct PointerCastPayload
{
    address: *void?
    size:    u64
}

struct SinglePointerCastPayload
{
    address: *void?
}

func semaTest007()
{
    let payload = PointerCastPayload{address: cast(*void?) 0x1234'u64, size: 16}
    let address = payload.address
    let size    = payload.size

    let single: SinglePointerCastPayload = cast(*void?) 0x5678'u64
    let singleAddress = single.address
}

// Indexing or selecting through a pointer made from a by-value parameter writes the memory that
// pointer designates, never the parameter. Each helper is a single statement, so it is inlined
// and its parameter bound to the caller's expression; that binding is read-only, and the write
// through the pointer must still be accepted.
struct PointerIntegerPair
{
    first:  u64
    second: u64
}

func writeSecondWord(address: u64)
{
    (cast([*] u64) address)[1] = 2
}

func writeFirstField(address: u64)
{
    (cast(*PointerIntegerPair) address).first = 1
}

func writeThroughField(pair: PointerIntegerPair)
{
    (cast([*] u64) pair.first)[0] = 3
}

func semaTest008()
{
    var words: [2] u64
    writeSecondWord(cast(u64) &words[0])
    writeFirstField(cast(u64) &words[0])
    writeThroughField(PointerIntegerPair{first: cast(u64) &words[0]})
}
