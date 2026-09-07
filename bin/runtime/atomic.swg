#global namespace Swag

// Integer storage whose every access is one indivisible operation.
//
// `T` is one of the sized integer types. Reads and writes go through this type's operations
// only: an ordinary read or write of the same storage beside them is a data race, so the field
// is not part of the API. Every operation is sequentially consistent.
//
// ```swag
// var counter: Swag.AtomicValue'u32
// counter.add(1)
// Swag.assert(counter.load() == 1)
// ```
struct(T) AtomicValue
{
    // Storage reached only through the atomic operations.
    #[Swag.NoDoc]
    storage: T
}

impl AtomicValue
{
    // Returns the current value.
    mtd const load()->T => Swag.atomget(cast #unconst (*T) &.storage)

    // Replaces the value.
    mtd store(value: T)
    {
        discard Swag.atomxchg(&.storage, value)
    }

    // Replaces the value and returns what it was.
    mtd exchange(value: T)->T => Swag.atomxchg(&.storage, value)

    // Replaces the value with `value` only if it currently equals `compare`.
    //
    // Returns the value found before the attempt, so the exchange succeeded when the result
    // equals `compare`.
    mtd compareExchange(compare, value: T)->T => Swag.atomcmpxchg(&.storage, compare, value)

    // Adds `value` and returns the value held before the addition.
    #[Swag.Discardable]
    mtd add(value: T)->T => Swag.atomadd(&.storage, value)

    // Subtracts `value` and returns the value held before the subtraction.
    #[Swag.Discardable]
    mtd sub(value: T)->T => Swag.atomadd(&.storage, cast #wrap (T) (~value + #wrap 1))

    // Applies a bitwise and, and returns the value held before it.
    #[Swag.Discardable]
    mtd bitAnd(value: T)->T => Swag.atomand(&.storage, value)

    // Applies a bitwise or, and returns the value held before it.
    #[Swag.Discardable]
    mtd bitOr(value: T)->T => Swag.atomor(&.storage, value)

    // Applies a bitwise exclusive or, and returns the value held before it.
    #[Swag.Discardable]
    mtd bitXor(value: T)->T => Swag.atomxor(&.storage, value)
}

// A one-way flag that any thread can raise and every thread can observe.
//
// A zero-initialized value is lowered. Raising is idempotent, so a request that several threads
// make at once is one request; nothing lowers a flag except an explicit [[Swag.AtomicFlag.reset]] on a
// value no other thread can still reach.
struct AtomicFlag
{
    // Raised state, reached only through the flag operations.
    #[Swag.NoDoc]
    state: AtomicValue'u32
}

impl AtomicFlag
{
    // Raises the flag, and returns whether this call is the one that raised it.
    #[Swag.Discardable]
    mtd raise()->bool => .state.exchange(1) == 0

    // Returns whether the flag is raised.
    mtd const isRaised()->bool => .state.load() != 0

    // Lowers the flag. Valid only while no other thread can reach it.
    mtd reset() => .state.store(0)
}
