#global namespace Swag

// Integer storage whose every access is one indivisible operation.
//
// `T` is one of the sized integer types. Reads and writes go through this type's operations
// only: an ordinary read or write of the same storage beside them is a data race, so the field
// is not part of the API.
//
// The plain operations are sequentially consistent: every thread observes all of them in one
// order. [[Swag.AtomicValue.loadAcquire]] and [[Swag.AtomicValue.storeRelease]] order only what
// one thread publishes to another, and the relaxed forms order nothing beyond the value itself.
// A weaker form does not keep the plain form's guarantee, so use one only with a stated reason;
// the memory model of the language reference says what each promises. Read-modify-write
// operations are always sequentially consistent.
//
// ```swag
// var counter: Swag.AtomicValue'u32
// counter.add(1)
// Swag.assert(counter.load() == 1)
// ```
struct(T) AtomicValue
{
    // Storage reached only through the atomic operations.
    storage: T
}

impl AtomicValue
{
    // Returns the current value.
    mtd const load()->T => Swag.atomicLoad(cast #unconst (*T, &.storage))

    // Returns the current value. When it was written by [[Swag.AtomicValue.storeRelease]],
    // everything the writing thread did before that write is visible after this read.
    mtd const loadAcquire()->T => Swag.atomicLoad(cast #unconst (*T, &.storage))

    // Returns the current value, ordered against nothing else: for a count or a statistic that no
    // other access depends on.
    mtd const loadRelaxed()->T => Swag.atomicLoad(cast #unconst (*T, &.storage))

    // Replaces the value.
    mtd store(value: T) { discard Swag.atomicExchange(&.storage, value) }

    // Replaces the value. A thread whose [[Swag.AtomicValue.loadAcquire]] reads it also sees
    // everything this thread wrote before: the way to publish data behind a flag, or to release a
    // lock. It does not order a later read of this thread against it, which is what the plain
    // [[Swag.AtomicValue.store]] is for.
    mtd storeRelease(value: T) => Swag.atomicStore(&.storage, value)

    // Replaces the value, ordered against nothing else.
    mtd storeRelaxed(value: T) => Swag.atomicStore(&.storage, value)

    // Replaces the value and returns what it was.
    mtd exchange(value: T)->T => Swag.atomicExchange(&.storage, value)

    // Replaces the value with `value` only if it currently equals `compare`.
    //
    // Returns the value found before the attempt, so the exchange succeeded when the result
    // equals `compare`.
    mtd compareExchange(compare, value: T)->T => Swag.atomicCompareExchange(&.storage, compare, value)

    // Adds `value` and returns the value held before the addition.
    #[Swag.Discardable]
    mtd add(value: T)->T => Swag.atomicAdd(&.storage, value)

    // Subtracts `value` and returns the value held before the subtraction.
    #[Swag.Discardable]
    mtd sub(value: T)->T => Swag.atomicAdd(&.storage, cast #wrap (T, (~value + #wrap 1)))

    // Applies a bitwise and, and returns the value held before it.
    #[Swag.Discardable]
    mtd bitAnd(value: T)->T => Swag.atomicAnd(&.storage, value)

    // Applies a bitwise or, and returns the value held before it.
    #[Swag.Discardable]
    mtd bitOr(value: T)->T => Swag.atomicOr(&.storage, value)

    // Applies a bitwise exclusive or, and returns the value held before it.
    #[Swag.Discardable]
    mtd bitXor(value: T)->T => Swag.atomicXor(&.storage, value)
}

// A one-way flag that any thread can raise and every thread can observe.
//
// A zero-initialized value is lowered. Raising is idempotent, so a request that several threads
// make at once is one request; nothing lowers a flag except an explicit [[Swag.AtomicFlag.reset]] on a
// value no other thread can still reach.
struct AtomicFlag
{
    // Raised state, reached only through the flag operations.
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
