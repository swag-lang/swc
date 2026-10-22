// Checks a programmer invariant and stops execution when it is false.
//
// Assertions are controlled by [[Swag.SafetyWhat.Assert]] in [[Swag.Build.Config.safetyGuards]]
// and by [[Swag.Safety]] overrides. They are enabled by default in devmode and by the
// 'test' command in every configuration, including release. Other release commands
// disable them by default. Explicit [[Swag.Safety]] overrides still apply in tests.
// Disabled assertions emit no code and evaluate none of their arguments; their arguments
// still need to type-check. Keep required side effects outside assertions.
// The optional message and source location are evaluated only when the condition is false.
// The condition establishes flow-narrowing facts for subsequent code even when disabled:
// callers remain responsible for the invariant. Use '#assert' for unconditional compile-time checks.
func assert(value: bool, message: string? = null, loc = #callerlocation)

// Stops execution in the attached debugger, as a breakpoint instruction.
func breakpoint()

// Returns the context of the current thread.
func getContext()->*Swag.Context

// Makes `context` the context of the current thread.
func setContext(context: const *Swag.Context)

// Returns the description of the current process.
func processInfo()->*Swag.ProcessInfo

// Returns every loaded module.
func modules()->const [..] Swag.Module?

// Returns the global variables the runtime drops when the process exits.
func globalsToDrop()->const [..] Swag.GlobalToDrop?

// Returns an [[ICompiler]] interface to communicate with the compiler.
func compiler()->Swag.ICompiler

// Sets the `size` bytes at `dst` to `value`.
//
// `dst` must be non-null, including when `size` is zero.
func memset(dst: [*] void, value: u8, size: u64)

// Copies `size` bytes from `src` to `dst`; the two blocks must not overlap.
//
// Both pointers must be non-null, including when `size` is zero.
func memcpy(dst: [*] void, src: const [*] void, size: u64)

// Copies `size` bytes from `src` to `dst`, which may overlap.
//
// Both pointers must be non-null, including when `size` is zero.
func memmove(dst: [*] void, src: const [*] void, size: u64)

// Compares `size` bytes and returns a negative value, zero, or a positive value.
//
// The sign gives the lexicographic order of the first differing unsigned bytes.
// A zero `size` compares equal; both pointers must still be non-null.
#[Swag.ReadOnly]
func memcmp(dst, src: const [*] void, size: u64)->s32

// Hints that the bytes at `addr` will be read soon, so the processor can start moving their cache line closer.
//
// It never faults and changes nothing the program can observe: `addr` may be null, dangling, or one past the
// end of a buffer, and a target without a prefetch instruction treats the call as a no-op.
func prefetch(addr: const [*] void)

// Atomic read-modify-write operations. Each one returns the value `addr` held before it.
#[Swag.Discardable]
{
    // Adds `value` to the integer at `addr`, atomically.
    func atomicAdd(addr: *s8, value: s8)->s8
    func atomicAdd(addr: *s16, value: s16)->s16
    func atomicAdd(addr: *s32, value: s32)->s32
    func atomicAdd(addr: *s64, value: s64)->s64
    func atomicAdd(addr: *u8, value: u8)->u8
    func atomicAdd(addr: *u16, value: u16)->u16
    func atomicAdd(addr: *u32, value: u32)->u32
    func atomicAdd(addr: *u64, value: u64)->u64

    // Combines `value` into the integer at `addr` with a bitwise and, atomically.
    func atomicAnd(addr: *s8, value: s8)->s8
    func atomicAnd(addr: *s16, value: s16)->s16
    func atomicAnd(addr: *s32, value: s32)->s32
    func atomicAnd(addr: *s64, value: s64)->s64
    func atomicAnd(addr: *u8, value: u8)->u8
    func atomicAnd(addr: *u16, value: u16)->u16
    func atomicAnd(addr: *u32, value: u32)->u32
    func atomicAnd(addr: *u64, value: u64)->u64

    // Combines `value` into the integer at `addr` with a bitwise or, atomically.
    func atomicOr(addr: *s8, value: s8)->s8
    func atomicOr(addr: *s16, value: s16)->s16
    func atomicOr(addr: *s32, value: s32)->s32
    func atomicOr(addr: *s64, value: s64)->s64
    func atomicOr(addr: *u8, value: u8)->u8
    func atomicOr(addr: *u16, value: u16)->u16
    func atomicOr(addr: *u32, value: u32)->u32
    func atomicOr(addr: *u64, value: u64)->u64

    // Combines `value` into the integer at `addr` with a bitwise xor, atomically.
    func atomicXor(addr: *s8, value: s8)->s8
    func atomicXor(addr: *s16, value: s16)->s16
    func atomicXor(addr: *s32, value: s32)->s32
    func atomicXor(addr: *s64, value: s64)->s64
    func atomicXor(addr: *u8, value: u8)->u8
    func atomicXor(addr: *u16, value: u16)->u16
    func atomicXor(addr: *u32, value: u32)->u32
    func atomicXor(addr: *u64, value: u64)->u64

    // Stores `exchangeWith` at `addr`, atomically.
    func atomicExchange(addr: *s8, exchangeWith: s8)->s8
    func atomicExchange(addr: *s16, exchangeWith: s16)->s16
    func atomicExchange(addr: *s32, exchangeWith: s32)->s32
    func atomicExchange(addr: *s64, exchangeWith: s64)->s64
    func atomicExchange(addr: *u8, exchangeWith: u8)->u8
    func atomicExchange(addr: *u16, exchangeWith: u16)->u16
    func atomicExchange(addr: *u32, exchangeWith: u32)->u32
    func atomicExchange(addr: *u64, exchangeWith: u64)->u64

    // Stores `exchangeWith` at `addr` when it holds `compareTo`, atomically.
    func atomicCompareExchange(addr: *s8, compareTo, exchangeWith: s8)->s8
    func atomicCompareExchange(addr: *s16, compareTo, exchangeWith: s16)->s16
    func atomicCompareExchange(addr: *s32, compareTo, exchangeWith: s32)->s32
    func atomicCompareExchange(addr: *s64, compareTo, exchangeWith: s64)->s64
    func atomicCompareExchange(addr: *u8, compareTo, exchangeWith: u8)->u8
    func atomicCompareExchange(addr: *u16, compareTo, exchangeWith: u16)->u16
    func atomicCompareExchange(addr: *u32, compareTo, exchangeWith: u32)->u32
    func atomicCompareExchange(addr: *u64, compareTo, exchangeWith: u64)->u64
}

// Reads the value at `addr` as one atomic access.
//
// It is a plain load on x86-64, so it takes no bus lock, and the compiler never hoists,
// merges, or drops it: a loop polling a value another thread publishes reads memory on
// every iteration.
func atomicLoad(addr: *s8)->s8
func atomicLoad(addr: *s16)->s16
func atomicLoad(addr: *s32)->s32
func atomicLoad(addr: *s64)->s64
func atomicLoad(addr: *u8)->u8
func atomicLoad(addr: *u16)->u16
func atomicLoad(addr: *u32)->u32
func atomicLoad(addr: *u64)->u64

// Writes `value` at `addr` as one atomic access.
//
// It is a plain store on x86-64, so it takes no bus lock where [[Swag.atomicExchange]] does, and the
// compiler never drops, merges, or moves another access across it: everything written before it
// is visible to a thread that reads the value with [[Swag.atomicLoad]].
func atomicStore(addr: *s8, value: s8)
func atomicStore(addr: *s16, value: s16)
func atomicStore(addr: *s32, value: s32)
func atomicStore(addr: *s64, value: s64)
func atomicStore(addr: *u8, value: u8)
func atomicStore(addr: *u16, value: u16)
func atomicStore(addr: *u32, value: u32)
func atomicStore(addr: *u64, value: u64)

// Intrinsics also evaluated at compile time.
#[Swag.ConstExpr]
{
    // Returns the square root of `value`.
    func sqrt(value: f32)->f32
    func sqrt(value: f64)->f64

    // Returns the smaller of two values.
    func min(value1, value2: s8)->s8
    func min(value1, value2: s16)->s16
    func min(value1, value2: s32)->s32
    func min(value1, value2: s64)->s64
    func min(value1, value2: u8)->u8
    func min(value1, value2: u16)->u16
    func min(value1, value2: u32)->u32
    func min(value1, value2: u64)->u64
    func min(value1, value2: f32)->f32
    func min(value1, value2: f64)->f64

    // Returns the larger of two values.
    func max(value1, value2: s8)->s8
    func max(value1, value2: s16)->s16
    func max(value1, value2: s32)->s32
    func max(value1, value2: s64)->s64
    func max(value1, value2: u8)->u8
    func max(value1, value2: u16)->u16
    func max(value1, value2: u32)->u32
    func max(value1, value2: u64)->u64
    func max(value1, value2: f32)->f32
    func max(value1, value2: f64)->f64

    // Returns the absolute value of `value`.
    func abs(value: s8)->s8
    func abs(value: s16)->s16
    func abs(value: s32)->s32
    func abs(value: s64)->s64
    func abs(value: f32)->f32
    func abs(value: f64)->f64

    // Rotates the bits of `value` left by `num` positions.
    func rol(value: u8, num: u8)->u8
    func rol(value: u16, num: u8)->u16
    func rol(value: u32, num: u8)->u32
    func rol(value: u64, num: u8)->u64

    // Rotates the bits of `value` right by `num` positions.
    func ror(value: u8, num: u8)->u8
    func ror(value: u16, num: u8)->u16
    func ror(value: u32, num: u8)->u32
    func ror(value: u64, num: u8)->u64

    // Reverses the order of bytes in an integer.
    func byteSwap(value: u16)->u16
    func byteSwap(value: u32)->u32
    func byteSwap(value: u64)->u64

    // Returns the number of bits set to 1.
    func countOnes(value: u8)->u8
    func countOnes(value: u16)->u16
    func countOnes(value: u32)->u32
    func countOnes(value: u64)->u64

    // Returns the number of zero bits below the lowest set bit, or the operand width when `value` is zero.
    func trailingZeros(value: u8)->u8
    func trailingZeros(value: u16)->u16
    func trailingZeros(value: u32)->u32
    func trailingZeros(value: u64)->u64

    // Returns the number of zero bits above the highest set bit, or the operand width when `value` is zero.
    func leadingZeros(value: u8)->u8
    func leadingZeros(value: u16)->u16
    func leadingZeros(value: u32)->u32
    func leadingZeros(value: u64)->u64

    // Returns '(val1 * val2) + val3'.
    //
    // The product rounds to the result type before the addition, even when the build
    // enables floating-point contraction.
    func mulAdd(val1, val2, val3: f32)->f32
    func mulAdd(val1, val2, val3: f64)->f64

    // Rounds toward minus infinity.
    func floor(value: f32)->f32
    func floor(value: f64)->f64

    // Rounds toward plus infinity.
    func ceil(value: f32)->f32
    func ceil(value: f64)->f64

    // Rounds toward zero.
    func trunc(value: f32)->f32
    func trunc(value: f64)->f64

    // Rounds to the nearest integer, halfway cases away from zero.
    func round(value: f32)->f32
    func round(value: f64)->f64
}

// Packed vector intrinsics. Every operation maps to one hardware form of the
// baseline instruction set; none folds into a compile-time constant, but all
// of them execute under compile-time evaluation like any other code.
{
    // Element-wise minimum and maximum.
    func min(value1, value2: #simd [16] u8)->#simd [16] u8
    func min(value1, value2: #simd [16] s8)->#simd [16] s8
    func min(value1, value2: #simd [8] u16)->#simd [8] u16
    func min(value1, value2: #simd [8] s16)->#simd [8] s16
    func min(value1, value2: #simd [4] u32)->#simd [4] u32
    func min(value1, value2: #simd [4] s32)->#simd [4] s32
    func min(value1, value2: #simd [2] u64)->#simd [2] u64
    func min(value1, value2: #simd [2] s64)->#simd [2] s64
    func min(value1, value2: #simd [4] f32)->#simd [4] f32
    func min(value1, value2: #simd [2] f64)->#simd [2] f64
    func max(value1, value2: #simd [16] u8)->#simd [16] u8
    func max(value1, value2: #simd [16] s8)->#simd [16] s8
    func max(value1, value2: #simd [8] u16)->#simd [8] u16
    func max(value1, value2: #simd [8] s16)->#simd [8] s16
    func max(value1, value2: #simd [4] u32)->#simd [4] u32
    func max(value1, value2: #simd [4] s32)->#simd [4] s32
    func max(value1, value2: #simd [2] u64)->#simd [2] u64
    func max(value1, value2: #simd [2] s64)->#simd [2] s64
    func max(value1, value2: #simd [4] f32)->#simd [4] f32
    func max(value1, value2: #simd [2] f64)->#simd [2] f64

    // Element-wise absolute value and square root. A float lane clears its sign
    // bit, so a NaN stays that NaN and a negative zero becomes a positive one.
    func abs(value: #simd [16] s8)->#simd [16] s8
    func abs(value: #simd [8] s16)->#simd [8] s16
    func abs(value: #simd [4] s32)->#simd [4] s32
    func abs(value: #simd [2] s64)->#simd [2] s64
    func abs(value: #simd [4] f32)->#simd [4] f32
    func abs(value: #simd [2] f64)->#simd [2] f64
    func sqrt(value: #simd [4] f32)->#simd [4] f32
    func sqrt(value: #simd [2] f64)->#simd [2] f64

    // Element-wise bit rotation. Every lane rotates by 'num' taken modulo the
    // lane width, exactly like the scalar forms.
    func rol(value: #simd [16] u8, num: u8)->#simd [16] u8
    func rol(value: #simd [8] u16, num: u8)->#simd [8] u16
    func rol(value: #simd [4] u32, num: u8)->#simd [4] u32
    func rol(value: #simd [2] u64, num: u8)->#simd [2] u64
    func ror(value: #simd [16] u8, num: u8)->#simd [16] u8
    func ror(value: #simd [8] u16, num: u8)->#simd [8] u16
    func ror(value: #simd [4] u32, num: u8)->#simd [4] u32
    func ror(value: #simd [2] u64, num: u8)->#simd [2] u64

    // Element-wise bit counts, each lane answering what the scalar form answers
    // for one value of that width.
    func countOnes(value: #simd [16] u8)->#simd [16] u8
    func countOnes(value: #simd [8] u16)->#simd [8] u16
    func countOnes(value: #simd [4] u32)->#simd [4] u32
    func countOnes(value: #simd [2] u64)->#simd [2] u64
    func trailingZeros(value: #simd [16] u8)->#simd [16] u8
    func trailingZeros(value: #simd [8] u16)->#simd [8] u16
    func trailingZeros(value: #simd [4] u32)->#simd [4] u32
    func trailingZeros(value: #simd [2] u64)->#simd [2] u64
    func leadingZeros(value: #simd [16] u8)->#simd [16] u8
    func leadingZeros(value: #simd [8] u16)->#simd [8] u16
    func leadingZeros(value: #simd [4] u32)->#simd [4] u32
    func leadingZeros(value: #simd [2] u64)->#simd [2] u64

    // Element-wise byte reversal inside every lane.
    func byteSwap(value: #simd [8] u16)->#simd [8] u16
    func byteSwap(value: #simd [4] u32)->#simd [4] u32
    func byteSwap(value: #simd [2] u64)->#simd [2] u64

    // Element-wise '(val1 * val2) + val3'.
    //
    // Each lane rounds its product to the element type before the addition, even when
    // the build enables floating-point contraction.
    func mulAdd(val1, val2, val3: #simd [4] f32)->#simd [4] f32
    func mulAdd(val1, val2, val3: #simd [2] f64)->#simd [2] f64

    // Element-wise float rounding. There is no packed round-away-from-zero.
    func floor(value: #simd [4] f32)->#simd [4] f32
    func floor(value: #simd [2] f64)->#simd [2] f64
    func ceil(value: #simd [4] f32)->#simd [4] f32
    func ceil(value: #simd [2] f64)->#simd [2] f64
    func trunc(value: #simd [4] f32)->#simd [4] f32
    func trunc(value: #simd [2] f64)->#simd [2] f64

    // Broadcast: every lane of the result takes the value of the scalar.
    //
    // The lane type names the vector, so a 'u8' fills sixteen lanes and an 'f64' fills two.
    func vecSplat(value: u8)->#simd [16] u8
    func vecSplat(value: s8)->#simd [16] s8
    func vecSplat(value: u16)->#simd [8] u16
    func vecSplat(value: s16)->#simd [8] s16
    func vecSplat(value: u32)->#simd [4] u32
    func vecSplat(value: s32)->#simd [4] s32
    func vecSplat(value: u64)->#simd [2] u64
    func vecSplat(value: s64)->#simd [2] s64
    func vecSplat(value: f32)->#simd [4] f32
    func vecSplat(value: f64)->#simd [2] f64

    // Saturating addition and subtraction: results clamp to the lane range instead of wrapping.
    func vecSatAdd(value1, value2: #simd [16] u8)->#simd [16] u8
    func vecSatAdd(value1, value2: #simd [16] s8)->#simd [16] s8
    func vecSatAdd(value1, value2: #simd [8] u16)->#simd [8] u16
    func vecSatAdd(value1, value2: #simd [8] s16)->#simd [8] s16
    func vecSatSub(value1, value2: #simd [16] u8)->#simd [16] u8
    func vecSatSub(value1, value2: #simd [16] s8)->#simd [16] s8
    func vecSatSub(value1, value2: #simd [8] u16)->#simd [8] u16
    func vecSatSub(value1, value2: #simd [8] s16)->#simd [8] s16

    // Narrows and clamps the lanes of 'low' and 'high' to the destination range.
    //
    // Saturating narrowing packs: the lanes of 'low' land in the low half of the result and the lanes of
    // 'high' in the high half, each clamped to the destination range.
    func vecNarrowSatU(low, high: #simd [8] s16)->#simd [16] u8
    func vecNarrowSatU(low, high: #simd [4] s32)->#simd [8] u16
    func vecNarrowSatS(low, high: #simd [8] s16)->#simd [16] s8
    func vecNarrowSatS(low, high: #simd [4] s32)->#simd [8] s16
    func vecInterleaveLo(value1, value2: #simd [16] u8)->#simd [16] u8
    func vecInterleaveLo(value1, value2: #simd [8] u16)->#simd [8] u16
    func vecInterleaveLo(value1, value2: #simd [4] u32)->#simd [4] u32
    func vecInterleaveLo(value1, value2: #simd [2] u64)->#simd [2] u64
    func vecInterleaveHi(value1, value2: #simd [16] u8)->#simd [16] u8
    func vecInterleaveHi(value1, value2: #simd [8] u16)->#simd [8] u16
    func vecInterleaveHi(value1, value2: #simd [4] u32)->#simd [4] u32
    func vecInterleaveHi(value1, value2: #simd [2] u64)->#simd [2] u64

    // Widens the low or high half of the lanes to double their width.
    //
    // Unsigned lanes are zero-extended; signed lanes are sign-extended.
    func vecWidenLo(value: #simd [16] u8)->#simd [8] u16
    func vecWidenLo(value: #simd [16] s8)->#simd [8] s16
    func vecWidenLo(value: #simd [8] u16)->#simd [4] u32
    func vecWidenLo(value: #simd [8] s16)->#simd [4] s32
    func vecWidenLo(value: #simd [4] u32)->#simd [2] u64
    func vecWidenLo(value: #simd [4] s32)->#simd [2] s64
    func vecWidenHi(value: #simd [16] u8)->#simd [8] u16
    func vecWidenHi(value: #simd [16] s8)->#simd [8] s16
    func vecWidenHi(value: #simd [8] u16)->#simd [4] u32
    func vecWidenHi(value: #simd [8] s16)->#simd [4] s32
    func vecWidenHi(value: #simd [4] u32)->#simd [2] u64
    func vecWidenHi(value: #simd [4] s32)->#simd [2] s64

    // Rounding average: '(a + b + 1) >> 1' per lane, without overflow.
    func vecAvgRound(value1, value2: #simd [16] u8)->#simd [16] u8
    func vecAvgRound(value1, value2: #simd [8] u16)->#simd [8] u16

    // Pairwise multiply-add: lanes multiply pairwise and adjacent products add into double-width lanes.
    //
    // The unsigned/signed byte form saturates its 16-bit sums.
    func vecMulAddPairs(value1, value2: #simd [8] s16)->#simd [4] s32
    func vecMulAddPairsSat(value1: #simd [16] u8, value2: #simd [16] s8)->#simd [8] s16

    // Carry-less multiplication of one 64-bit half of each source into a full 128-bit product.
    //
    // Bit 0 of the constant 'selector' picks the half of 'value1' and bit 4 the half of 'value2'. This is what
    // CRC folding is made of.
    func vecCarrylessMul(value1, value2: #simd [2] u64, selector: u8)->#simd [2] u64

    // The high half of each lane product, using the lane type's signedness.
    //
    // The half of a lane product that '*' drops: lane 'i' answers the bits above the lane width of the full
    // product of both lane 'i' values, read as the lane type is signed or not. The two together are the whole
    // product, low lanes in 'Swag.vecInterleaveLo' and high lanes in 'Swag.vecInterleaveHi'.
    func vecMulHigh(value1, value2: #simd [16] u8)->#simd [16] u8
    func vecMulHigh(value1, value2: #simd [16] s8)->#simd [16] s8
    func vecMulHigh(value1, value2: #simd [8] u16)->#simd [8] u16
    func vecMulHigh(value1, value2: #simd [8] s16)->#simd [8] s16
    func vecMulHigh(value1, value2: #simd [4] u32)->#simd [4] u32
    func vecMulHigh(value1, value2: #simd [4] s32)->#simd [4] s32
    func vecMulHigh(value1, value2: #simd [2] u64)->#simd [2] u64
    func vecMulHigh(value1, value2: #simd [2] s64)->#simd [2] s64

    // Sums absolute byte differences in each 64-bit lane.
    //
    // Each half of the operands reduces into the low word of the matching lane.
    func vecSumAbsDiff(value1, value2: #simd [16] u8)->#simd [2] u64
    func vecSumAbsDiff(value1, value2: #simd [16] s8)->#simd [2] u64

    // Horizontal reductions: every lane combines into one scalar of the lane type.
    //
    // Adjacent lanes combine first and their results after, so the order is a balanced tree over the lane
    // index. Integer sums wrap, and the float minimum and maximum follow the element-wise 'Swag.min' and
    // 'Swag.max', which answer their second operand when either side is a NaN.
    func vecReduceAdd(value: #simd [16] u8)->u8
    func vecReduceAdd(value: #simd [16] s8)->s8
    func vecReduceAdd(value: #simd [8] u16)->u16
    func vecReduceAdd(value: #simd [8] s16)->s16
    func vecReduceAdd(value: #simd [4] u32)->u32
    func vecReduceAdd(value: #simd [4] s32)->s32
    func vecReduceAdd(value: #simd [2] u64)->u64
    func vecReduceAdd(value: #simd [2] s64)->s64
    func vecReduceAdd(value: #simd [4] f32)->f32
    func vecReduceAdd(value: #simd [2] f64)->f64
    func vecReduceMin(value: #simd [16] u8)->u8
    func vecReduceMin(value: #simd [16] s8)->s8
    func vecReduceMin(value: #simd [8] u16)->u16
    func vecReduceMin(value: #simd [8] s16)->s16
    func vecReduceMin(value: #simd [4] u32)->u32
    func vecReduceMin(value: #simd [4] s32)->s32
    func vecReduceMin(value: #simd [2] u64)->u64
    func vecReduceMin(value: #simd [2] s64)->s64
    func vecReduceMin(value: #simd [4] f32)->f32
    func vecReduceMin(value: #simd [2] f64)->f64
    func vecReduceMax(value: #simd [16] u8)->u8
    func vecReduceMax(value: #simd [16] s8)->s8
    func vecReduceMax(value: #simd [8] u16)->u16
    func vecReduceMax(value: #simd [8] s16)->s16
    func vecReduceMax(value: #simd [4] u32)->u32
    func vecReduceMax(value: #simd [4] s32)->s32
    func vecReduceMax(value: #simd [2] u64)->u64
    func vecReduceMax(value: #simd [2] s64)->s64
    func vecReduceMax(value: #simd [4] f32)->f32
    func vecReduceMax(value: #simd [2] f64)->f64
    func vecReduceAnd(value: #simd [16] u8)->u8
    func vecReduceAnd(value: #simd [16] s8)->s8
    func vecReduceAnd(value: #simd [8] u16)->u16
    func vecReduceAnd(value: #simd [8] s16)->s16
    func vecReduceAnd(value: #simd [4] u32)->u32
    func vecReduceAnd(value: #simd [4] s32)->s32
    func vecReduceAnd(value: #simd [2] u64)->u64
    func vecReduceAnd(value: #simd [2] s64)->s64
    func vecReduceOr(value: #simd [16] u8)->u8
    func vecReduceOr(value: #simd [16] s8)->s8
    func vecReduceOr(value: #simd [8] u16)->u16
    func vecReduceOr(value: #simd [8] s16)->s16
    func vecReduceOr(value: #simd [4] u32)->u32
    func vecReduceOr(value: #simd [4] s32)->s32
    func vecReduceOr(value: #simd [2] u64)->u64
    func vecReduceOr(value: #simd [2] s64)->s64
    func vecReduceXor(value: #simd [16] u8)->u8
    func vecReduceXor(value: #simd [16] s8)->s8
    func vecReduceXor(value: #simd [8] u16)->u16
    func vecReduceXor(value: #simd [8] s16)->s16
    func vecReduceXor(value: #simd [4] u32)->u32
    func vecReduceXor(value: #simd [4] s32)->s32
    func vecReduceXor(value: #simd [2] u64)->u64
    func vecReduceXor(value: #simd [2] s64)->s64

    // Converts float lanes to signed 32-bit integers by truncating toward zero.
    //
    // NaN and values outside the destination range become 's32.Min'.
    func vecTruncToS32(value: #simd [4] f32)->#simd [4] s32

    // Indexed memory load: result lane i reads base[indices[i]].
    //
    // Every index must be at most 's32.Max' and designate a readable element.
    func vecGather(base: const [*] s32, indices: #simd [4] u32)->#simd [4] s32

    // Selects source bytes using the low four bits of each table byte.
    //
    // A result byte becomes zero when the matching table byte has its high bit set.
    func vecPermute(value: #simd [16] u8, table: #simd [16] u8)->#simd [16] u8

    // Lane permutation.
    //
    // Result lane 'i' takes the lane the matching pattern lane names, the index reduced modulo the lane count
    // so no pattern is out of range. A pattern known at compile time selects an immediate form where the
    // target has one, and one built at run time goes through the dynamic byte permute.
    func vecShuffle(value: #simd [16] u8, pattern: #simd [16] u8)->#simd [16] u8
    func vecShuffle(value: #simd [16] s8, pattern: #simd [16] u8)->#simd [16] s8
    func vecShuffle(value: #simd [8] u16, pattern: #simd [8] u16)->#simd [8] u16
    func vecShuffle(value: #simd [8] s16, pattern: #simd [8] u16)->#simd [8] s16
    func vecShuffle(value: #simd [4] u32, pattern: #simd [4] u32)->#simd [4] u32
    func vecShuffle(value: #simd [4] s32, pattern: #simd [4] u32)->#simd [4] s32
    func vecShuffle(value: #simd [2] u64, pattern: #simd [2] u64)->#simd [2] u64
    func vecShuffle(value: #simd [2] s64, pattern: #simd [2] u64)->#simd [2] s64
    func vecShuffle(value: #simd [4] f32, pattern: #simd [4] u32)->#simd [4] f32
    func vecShuffle(value: #simd [2] f64, pattern: #simd [2] u64)->#simd [2] f64

    // Shuffles lanes selected from two vectors.
    //
    // An index below the lane count reads 'value1'. An index at or above it reads
    // 'value2' at the index minus the lane count.
    func vecShuffle2(value1, value2: #simd [16] u8, pattern: #simd [16] u8)->#simd [16] u8
    func vecShuffle2(value1, value2: #simd [16] s8, pattern: #simd [16] u8)->#simd [16] s8
    func vecShuffle2(value1, value2: #simd [8] u16, pattern: #simd [8] u16)->#simd [8] u16
    func vecShuffle2(value1, value2: #simd [8] s16, pattern: #simd [8] u16)->#simd [8] s16
    func vecShuffle2(value1, value2: #simd [4] u32, pattern: #simd [4] u32)->#simd [4] u32
    func vecShuffle2(value1, value2: #simd [4] s32, pattern: #simd [4] u32)->#simd [4] s32
    func vecShuffle2(value1, value2: #simd [2] u64, pattern: #simd [2] u64)->#simd [2] u64
    func vecShuffle2(value1, value2: #simd [2] s64, pattern: #simd [2] u64)->#simd [2] s64
    func vecShuffle2(value1, value2: #simd [4] f32, pattern: #simd [4] u32)->#simd [4] f32
    func vecShuffle2(value1, value2: #simd [2] f64, pattern: #simd [2] u64)->#simd [2] f64

    // Sixteen bytes of the concatenation of 'low' and 'high', starting at byte 'count' of it.
    //
    // A byte past the thirty-two is zero.
    func vecAlign(low, high: #simd [16] u8, count: u8)->#simd [16] u8
    func vecAlign(low, high: #simd [16] s8, count: u8)->#simd [16] s8
    func vecAlign(low, high: #simd [8] u16, count: u8)->#simd [8] u16
    func vecAlign(low, high: #simd [8] s16, count: u8)->#simd [8] s16
    func vecAlign(low, high: #simd [4] u32, count: u8)->#simd [4] u32
    func vecAlign(low, high: #simd [4] s32, count: u8)->#simd [4] s32
    func vecAlign(low, high: #simd [2] u64, count: u8)->#simd [2] u64
    func vecAlign(low, high: #simd [2] s64, count: u8)->#simd [2] s64
    func vecAlign(low, high: #simd [4] f32, count: u8)->#simd [4] f32
    func vecAlign(low, high: #simd [2] f64, count: u8)->#simd [2] f64

    // Per-lane select: lanes of 'ifTrue' where the mask lane is all-ones, lanes of 'ifFalse' where it is all-zeros.
    func vecSelect(mask, ifTrue, ifFalse: #simd [16] u8)->#simd [16] u8
    func vecSelect(mask: #simd [8] u16, ifTrue, ifFalse: #simd [8] s16)->#simd [8] s16
    func vecSelect(mask, ifTrue, ifFalse: #simd [8] u16)->#simd [8] u16
    func vecSelect(mask: #simd [4] u32, ifTrue, ifFalse: #simd [4] s32)->#simd [4] s32
    func vecSelect(mask, ifTrue, ifFalse: #simd [4] u32)->#simd [4] u32
    func vecSelect(mask: #simd [4] u32, ifTrue, ifFalse: #simd [4] f32)->#simd [4] f32
    func vecSelect(mask: #simd [2] u64, ifTrue, ifFalse: #simd [2] f64)->#simd [2] f64
    func vecSelect(mask, ifTrue, ifFalse: #simd [2] u64)->#simd [2] u64
    func vecSelect(mask: #simd [2] u64, ifTrue, ifFalse: #simd [2] s64)->#simd [2] s64
    func vecSelect(mask: #simd [16] u8, ifTrue, ifFalse: #simd [16] s8)->#simd [16] s8

    // Lane sign bits gathered into the low bits of an integer: one bit per lane, lane zero in bit zero.
    func vecMask(value: #simd [16] u8)->u32
    func vecMask(value: #simd [8] u16)->u32
    func vecMask(value: #simd [4] u32)->u32
    func vecMask(value: #simd [2] u64)->u32

    // True when any (respectively every) mask lane is all-ones.
    func vecAny(value: #simd [16] u8)->bool
    func vecAny(value: #simd [8] u16)->bool
    func vecAny(value: #simd [4] u32)->bool
    func vecAny(value: #simd [2] u64)->bool
    func vecAll(value: #simd [16] u8)->bool
    func vecAll(value: #simd [8] u16)->bool
    func vecAll(value: #simd [4] u32)->bool
    func vecAll(value: #simd [2] u64)->bool
}

#[Swag.ConstExpr]
{
    // Trigonometric functions.
    func sin(value: f32)->f32
    func sin(value: f64)->f64
    func cos(value: f32)->f32
    func cos(value: f64)->f64
    func tan(value: f32)->f32
    func tan(value: f64)->f64

    // Hyperbolic trigonometric functions.
    func sinh(value: f32)->f32
    func sinh(value: f64)->f64
    func cosh(value: f32)->f32
    func cosh(value: f64)->f64
    func tanh(value: f32)->f32
    func tanh(value: f64)->f64

    // Inverse trigonometric functions.
    func asin(value: f32)->f32
    func asin(value: f64)->f64
    func acos(value: f32)->f32
    func acos(value: f64)->f64
    func atan(value: f32)->f32
    func atan(value: f64)->f64

    // Logarithms.
    func log(value: f32)->f32
    func log(value: f64)->f64
    func log2(value: f32)->f32
    func log2(value: f64)->f64
    func log10(value: f32)->f32
    func log10(value: f64)->f64

    // Exponentials and power.
    func exp(value: f32)->f32
    func exp(value: f64)->f64
    func exp2(value: f32)->f32
    func exp2(value: f64)->f64
    func pow(value1, value2: f32)->f32
    func pow(value1, value2: f64)->f64

    // Arctangent of y/x with quadrant selection.
    func atan2(value1, value2: f32)->f32
    func atan2(value1, value2: f64)->f64
}
