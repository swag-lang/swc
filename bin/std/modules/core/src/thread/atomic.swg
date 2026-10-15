#global public
#global namespace Atomic

#[Swag.Inline, Swag.Discardable]
{
    // Atomically adds `value` to the integer at `addr` and returns its previous value.
    func add(addr: *s8, value: s8)->s8    => Swag.atomicAdd(addr, value)
    func add(addr: *s16, value: s16)->s16 => Swag.atomicAdd(addr, value)
    func add(addr: *s32, value: s32)->s32 => Swag.atomicAdd(addr, value)
    func add(addr: *s64, value: s64)->s64 => Swag.atomicAdd(addr, value)
    func add(addr: *u8, value: u8)->u8    => Swag.atomicAdd(addr, value)
    func add(addr: *u16, value: u16)->u16 => Swag.atomicAdd(addr, value)
    func add(addr: *u32, value: u32)->u32 => Swag.atomicAdd(addr, value)
    func add(addr: *u64, value: u64)->u64 => Swag.atomicAdd(addr, value)

    // Atomically replaces the integer at `addr` with its bitwise AND with `value` and returns its previous value.
    func logicAnd(addr: *s8, value: s8)->s8    => Swag.atomicAnd(addr, value)
    func logicAnd(addr: *s16, value: s16)->s16 => Swag.atomicAnd(addr, value)
    func logicAnd(addr: *s32, value: s32)->s32 => Swag.atomicAnd(addr, value)
    func logicAnd(addr: *s64, value: s64)->s64 => Swag.atomicAnd(addr, value)
    func logicAnd(addr: *u8, value: u8)->u8    => Swag.atomicAnd(addr, value)
    func logicAnd(addr: *u16, value: u16)->u16 => Swag.atomicAnd(addr, value)
    func logicAnd(addr: *u32, value: u32)->u32 => Swag.atomicAnd(addr, value)
    func logicAnd(addr: *u64, value: u64)->u64 => Swag.atomicAnd(addr, value)

    // Atomically replaces the integer at `addr` with its bitwise OR with `value` and returns its previous value.
    func logicOr(addr: *s8, value: s8)->s8    => Swag.atomicOr(addr, value)
    func logicOr(addr: *s16, value: s16)->s16 => Swag.atomicOr(addr, value)
    func logicOr(addr: *s32, value: s32)->s32 => Swag.atomicOr(addr, value)
    func logicOr(addr: *s64, value: s64)->s64 => Swag.atomicOr(addr, value)
    func logicOr(addr: *u8, value: u8)->u8    => Swag.atomicOr(addr, value)
    func logicOr(addr: *u16, value: u16)->u16 => Swag.atomicOr(addr, value)
    func logicOr(addr: *u32, value: u32)->u32 => Swag.atomicOr(addr, value)
    func logicOr(addr: *u64, value: u64)->u64 => Swag.atomicOr(addr, value)

    // Atomically replaces the integer at `addr` with its bitwise XOR with `value` and returns its previous value.
    func logicXor(addr: *s8, value: s8)->s8    => Swag.atomicXor(addr, value)
    func logicXor(addr: *s16, value: s16)->s16 => Swag.atomicXor(addr, value)
    func logicXor(addr: *s32, value: s32)->s32 => Swag.atomicXor(addr, value)
    func logicXor(addr: *s64, value: s64)->s64 => Swag.atomicXor(addr, value)
    func logicXor(addr: *u8, value: u8)->u8    => Swag.atomicXor(addr, value)
    func logicXor(addr: *u16, value: u16)->u16 => Swag.atomicXor(addr, value)
    func logicXor(addr: *u32, value: u32)->u32 => Swag.atomicXor(addr, value)
    func logicXor(addr: *u64, value: u64)->u64 => Swag.atomicXor(addr, value)

    // Atomically stores `exchangeWith` at `addr` and returns the previous value.
    func exchange(addr: *s8, exchangeWith: s8)->s8    => Swag.atomicExchange(addr, exchangeWith)
    func exchange(addr: *s16, exchangeWith: s16)->s16 => Swag.atomicExchange(addr, exchangeWith)
    func exchange(addr: *s32, exchangeWith: s32)->s32 => Swag.atomicExchange(addr, exchangeWith)
    func exchange(addr: *s64, exchangeWith: s64)->s64 => Swag.atomicExchange(addr, exchangeWith)
    func exchange(addr: *u8, exchangeWith: u8)->u8    => Swag.atomicExchange(addr, exchangeWith)
    func exchange(addr: *u16, exchangeWith: u16)->u16 => Swag.atomicExchange(addr, exchangeWith)
    func exchange(addr: *u32, exchangeWith: u32)->u32 => Swag.atomicExchange(addr, exchangeWith)
    func exchange(addr: *u64, exchangeWith: u64)->u64 => Swag.atomicExchange(addr, exchangeWith)

    // Atomically stores `exchangeWith` at `addr` when it holds `compareTo`, and returns the previous value.
    //
    // The exchange happened when the returned value equals `compareTo`.
    func compareExchange(addr: *s8, compareTo, exchangeWith: s8)->s8    => Swag.atomicCompareExchange(addr, compareTo, exchangeWith)
    func compareExchange(addr: *s16, compareTo, exchangeWith: s16)->s16 => Swag.atomicCompareExchange(addr, compareTo, exchangeWith)
    func compareExchange(addr: *s32, compareTo, exchangeWith: s32)->s32 => Swag.atomicCompareExchange(addr, compareTo, exchangeWith)
    func compareExchange(addr: *s64, compareTo, exchangeWith: s64)->s64 => Swag.atomicCompareExchange(addr, compareTo, exchangeWith)
    func compareExchange(addr: *u8, compareTo, exchangeWith: u8)->u8    => Swag.atomicCompareExchange(addr, compareTo, exchangeWith)
    func compareExchange(addr: *u16, compareTo, exchangeWith: u16)->u16 => Swag.atomicCompareExchange(addr, compareTo, exchangeWith)
    func compareExchange(addr: *u32, compareTo, exchangeWith: u32)->u32 => Swag.atomicCompareExchange(addr, compareTo, exchangeWith)
    func compareExchange(addr: *u64, compareTo, exchangeWith: u64)->u64 => Swag.atomicCompareExchange(addr, compareTo, exchangeWith)

    // Reads the integer at `addr` as one atomic access, without locking the cache line.
    func get(addr: *s8)->s8   => Swag.atomicLoad(addr)
    func get(addr: *s16)->s16 => Swag.atomicLoad(addr)
    func get(addr: *s32)->s32 => Swag.atomicLoad(addr)
    func get(addr: *s64)->s64 => Swag.atomicLoad(addr)
    func get(addr: *u8)->u8   => Swag.atomicLoad(addr)
    func get(addr: *u16)->u16 => Swag.atomicLoad(addr)
    func get(addr: *u32)->u32 => Swag.atomicLoad(addr)
    func get(addr: *u64)->u64 => Swag.atomicLoad(addr)
}
