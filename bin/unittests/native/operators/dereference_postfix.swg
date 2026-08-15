#global private

// Read through the postfix dereference
#test
{
    var value = 42's32
    let p     = &value
    @assert(p[] == 42)
}

// Write through the postfix dereference
#test
{
    var value = 1's32
    let p     = &value
    p[] = 7
    @assert(value == 7)
}

// Compound assignment through the postfix dereference
#test
{
    var value = 40's32
    let p     = &value
    p[] += 2
    @assert(value == 42)
}

// Whole struct value read and replace
#test
{
    struct AA
    {
        x: s32
        y: s32
    }

    var st   = AA{x: 1, y: 2}
    let p    = &st
    var copy = p[]
    #assert(#typeof(copy) == AA)
    @assert(copy.x == 1 and copy.y == 2)
    p[] = AA{x: 3, y: 4}
    @assert(st.x == 3 and st.y == 4)
}

// The postfix dereference composes left-to-right through a double pointer
#test
{
    var value = 5's32
    var p     = &value
    var pp    = &p
    @assert(pp[][] == 5)
    pp[][] = 9
    @assert(value == 9)
}

// Postfix dereference then index
#test
{
    var arr: [3] s32 = [1, 2, 3]
    let p            = &arr
    @assert(p[][1] == 2)
    p[][2] = 9
    @assert(arr[2] == 9)
}

// 'expr[as T]' reads the pointed storage as a T of the same size
#test
{
    var bits = 0xFFFF_FFFF'u32
    let p    = &bits
    @assert(p[as s32] == -1)
}

// 'expr[as T]' writes through the reinterpreted place
#test
{
    var value = 0's32
    let p     = &value
    p[as u32] = 0xFFFF_FFFF
    @assert(value == -1)
}

// 'expr[as T]' opens a narrower window on the storage (x64 is little-endian)
#test
{
    var value = 0x0102_0304'u32
    let p     = &value
    @assert(p[as u8] == 0x04)
    p[as u8] = 0xFF
    @assert(value == 0x0102_03FF)
}

// 'expr[as T]' exposes the bit pattern of a float
#test
{
    var f = 1.0'f32
    let p = &f
    @assert(p[as u32] == 0x3F80_0000)
}

// A conversion around 'expr[as T]' converts the T that was read; it never widens the read
// itself. The conversion substitutes the dereference node, so a place typed from the live
// view would answer with the converted type and open an eight-byte window on a four-byte
// object - reading past the storage and returning whatever followed it.
func derefPlaceWidenS32(data: const *void)->s64
{
    return data[as s32]
}

func derefPlaceWidenU32(data: const *void)->u64
{
    return data[as u32]
}

func derefPlaceWidenF32(data: const *void)->f64
{
    return data[as f32]
}

#test
{
    var value: s32 = -7
    @assert(derefPlaceWidenS32(&value) == -7)

    var bits: u32 = 0xFFFF_FFFF
    @assert(derefPlaceWidenU32(&bits) == 0xFFFF_FFFF)

    var single: f32 = 1.5
    @assert(derefPlaceWidenF32(&single) == 1.5)
}

// The same conversion inside the caller's frame, where the neighbouring storage is a known
// value rather than whatever the stack held.
#test
{
    var pair:    [2] s32 = [-7, 0x7FFF_FFFF]
    let p                = &pair[0]
    let widened: s64     = p[as s32]
    @assert(widened == -7)
}

struct DerefPlaceReceiver
{
    seen: s64
}

impl DerefPlaceReceiver
{
    #[Swag.Implicit]
    mtd opSet(value: string) { .seen = cast(s64) @countof(value) }

    mtd(op: Swag.Operator) opAssign(value: s64)
        where op == .AddAssign
    {
        .seen += value
    }

    mtd record(value: s64) { .seen = value }
}

// A method call on the reinterpreted place receives the place itself as 'me'
#test
{
    var slot: DerefPlaceReceiver
    let p = cast(*void) &slot
    p[as DerefPlaceReceiver].record(11)
    @assert(slot.seen == 11)
}

// A member write through the reinterpreted place
#test
{
    var slot: DerefPlaceReceiver
    let p = cast(*void) &slot
    p[as DerefPlaceReceiver].seen = 5
    @assert(slot.seen == 5)
}

// An assignment routed through the implicit 'opSet' of the reinterpreted place
#test
{
    var slot: DerefPlaceReceiver
    let p = cast(*void) &slot
    p[as DerefPlaceReceiver] = "beta"
    @assert(slot.seen == 4)
}

// A compound assignment routed through 'opAssign' of the reinterpreted place
#test
{
    var slot: DerefPlaceReceiver
    let p = cast(*void) &slot
    p[as DerefPlaceReceiver] += 3
    @assert(slot.seen == 3)
}
