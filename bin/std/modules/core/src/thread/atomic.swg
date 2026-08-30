#global public
#global namespace Atomic

#[Swag.Inline, Swag.Discardable]
{
    // Performs the add operation.
    func add(addr: *s8, value: s8)->s8 => Swag.atomadd(addr, value)

    // Performs the add operation.
    func add(addr: *s16, value: s16)->s16 => Swag.atomadd(addr, value)
    func add(addr: *s32, value: s32)->s32 => Swag.atomadd(addr, value)
    func add(addr: *s64, value: s64)->s64 => Swag.atomadd(addr, value)
    func add(addr: *u8, value: u8)->u8    => Swag.atomadd(addr, value)
    func add(addr: *u16, value: u16)->u16 => Swag.atomadd(addr, value)
    func add(addr: *u32, value: u32)->u32 => Swag.atomadd(addr, value)
    func add(addr: *u64, value: u64)->u64 => Swag.atomadd(addr, value)

    // Performs the logic and operation.
    func logicAnd(addr: *s8, value: s8)->s8 => Swag.atomand(addr, value)

    // Performs the logic and operation.
    func logicAnd(addr: *s16, value: s16)->s16 => Swag.atomand(addr, value)
    func logicAnd(addr: *s32, value: s32)->s32 => Swag.atomand(addr, value)
    func logicAnd(addr: *s64, value: s64)->s64 => Swag.atomand(addr, value)
    func logicAnd(addr: *u8, value: u8)->u8    => Swag.atomand(addr, value)
    func logicAnd(addr: *u16, value: u16)->u16 => Swag.atomand(addr, value)
    func logicAnd(addr: *u32, value: u32)->u32 => Swag.atomand(addr, value)
    func logicAnd(addr: *u64, value: u64)->u64 => Swag.atomand(addr, value)

    // Performs the logic or operation.
    func logicOr(addr: *s8, value: s8)->s8 => Swag.atomor(addr, value)

    // Performs the logic or operation.
    func logicOr(addr: *s16, value: s16)->s16 => Swag.atomor(addr, value)
    func logicOr(addr: *s32, value: s32)->s32 => Swag.atomor(addr, value)
    func logicOr(addr: *s64, value: s64)->s64 => Swag.atomor(addr, value)
    func logicOr(addr: *u8, value: u8)->u8    => Swag.atomor(addr, value)
    func logicOr(addr: *u16, value: u16)->u16 => Swag.atomor(addr, value)
    func logicOr(addr: *u32, value: u32)->u32 => Swag.atomor(addr, value)
    func logicOr(addr: *u64, value: u64)->u64 => Swag.atomor(addr, value)

    // Performs the logic xor operation.
    func logicXor(addr: *s8, value: s8)->s8 => Swag.atomxor(addr, value)

    // Performs the logic xor operation.
    func logicXor(addr: *s16, value: s16)->s16 => Swag.atomxor(addr, value)
    func logicXor(addr: *s32, value: s32)->s32 => Swag.atomxor(addr, value)
    func logicXor(addr: *s64, value: s64)->s64 => Swag.atomxor(addr, value)
    func logicXor(addr: *u8, value: u8)->u8    => Swag.atomxor(addr, value)
    func logicXor(addr: *u16, value: u16)->u16 => Swag.atomxor(addr, value)
    func logicXor(addr: *u32, value: u32)->u32 => Swag.atomxor(addr, value)
    func logicXor(addr: *u64, value: u64)->u64 => Swag.atomxor(addr, value)

    // Performs the exchange operation.
    func exchange(addr: *s8, exchangeWith: s8)->s8 => Swag.atomxchg(addr, exchangeWith)

    // Performs the exchange operation.
    func exchange(addr: *s16, exchangeWith: s16)->s16 => Swag.atomxchg(addr, exchangeWith)
    func exchange(addr: *s32, exchangeWith: s32)->s32 => Swag.atomxchg(addr, exchangeWith)
    func exchange(addr: *s64, exchangeWith: s64)->s64 => Swag.atomxchg(addr, exchangeWith)
    func exchange(addr: *u8, exchangeWith: u8)->u8    => Swag.atomxchg(addr, exchangeWith)
    func exchange(addr: *u16, exchangeWith: u16)->u16 => Swag.atomxchg(addr, exchangeWith)
    func exchange(addr: *u32, exchangeWith: u32)->u32 => Swag.atomxchg(addr, exchangeWith)
    func exchange(addr: *u64, exchangeWith: u64)->u64 => Swag.atomxchg(addr, exchangeWith)

    // Performs the compare exchange operation.
    func compareExchange(addr: *s8, compareTo, exchangeWith: s8)->s8 => Swag.atomcmpxchg(addr, compareTo, exchangeWith)

    // Performs the compare exchange operation.
    func compareExchange(addr: *s16, compareTo, exchangeWith: s16)->s16 => Swag.atomcmpxchg(addr, compareTo, exchangeWith)
    func compareExchange(addr: *s32, compareTo, exchangeWith: s32)->s32 => Swag.atomcmpxchg(addr, compareTo, exchangeWith)
    func compareExchange(addr: *s64, compareTo, exchangeWith: s64)->s64 => Swag.atomcmpxchg(addr, compareTo, exchangeWith)
    func compareExchange(addr: *u8, compareTo, exchangeWith: u8)->u8    => Swag.atomcmpxchg(addr, compareTo, exchangeWith)
    func compareExchange(addr: *u16, compareTo, exchangeWith: u16)->u16 => Swag.atomcmpxchg(addr, compareTo, exchangeWith)
    func compareExchange(addr: *u32, compareTo, exchangeWith: u32)->u32 => Swag.atomcmpxchg(addr, compareTo, exchangeWith)
    func compareExchange(addr: *u64, compareTo, exchangeWith: u64)->u64 => Swag.atomcmpxchg(addr, compareTo, exchangeWith)

    // Performs the get operation.
    func get(addr: *s8)->s8 => Swag.atomcmpxchg(addr, 0, 0)

    // Performs the get operation.
    func get(addr: *s16)->s16 => Swag.atomcmpxchg(addr, 0, 0)
    func get(addr: *s32)->s32 => Swag.atomcmpxchg(addr, 0, 0)
    func get(addr: *s64)->s64 => Swag.atomcmpxchg(addr, 0, 0)
    func get(addr: *u8)->u8   => Swag.atomcmpxchg(addr, 0, 0)
    func get(addr: *u16)->u16 => Swag.atomcmpxchg(addr, 0, 0)
    func get(addr: *u32)->u32 => Swag.atomcmpxchg(addr, 0, 0)
    func get(addr: *u64)->u64 => Swag.atomcmpxchg(addr, 0, 0)
}
