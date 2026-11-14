#global public

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func minUnsigned(a, b, c: u64)->u64 => a < b ? a : b

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func maxUnsigned(a, b, c: u64)->u64 => a > b ? a : b

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func minSigned(a, b, c: s64)->s64 => a < b ? a : b

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func maxSigned(a, b, c: s64)->s64 => a > b ? a : b

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func clampUnsigned(a, b, c: u64)->u64 => a > 100 ? 100 : a

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func clampSigned(a, b, c: s64)->s64 => a < -10 ? -10 : a > 10 ? 10 : a

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func absSigned(a, b, c: s64)->u64 => a < 0 ? 0'u64 - (cast #bit (u64) a) : cast(u64) a

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func zeroSelect(a, b, c: u64)->u64 => a == 0 ? b : c

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func bitSelect(a, b, c: u64)->u64 => (a & 1) != 0 ? b : c

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func bitTimesValue(a, b, c: u64)->u64 => (a & 1) * b

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func addIfZero(a, b, c: u64)->u64 => a + (b == 0 ? 1'u64 : 0)

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func addIfNotZero(a, b, c: u64)->u64 => a + (b != 0 ? 1'u64 : 0)

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func subtractIfBelow(a, b, c: u64)->u64 => a - (b < c ? 1'u64 : 0)

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func addIfAboveEqual(a, b, c: u64)->u64 => a + (b >= c ? 1'u64 : 0)

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func equalMask(a, b, c: u64)->u64 => a == 0 ? 0xFFFFFFFFFFFFFFFF : 0

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func notEqualMask(a, b, c: u64)->u64 => a != 0 ? 0xFFFFFFFFFFFFFFFF : 0

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func factorProducts(a, b, c: u64)->u64 => a * b + a * c

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func subtractProducts(a, b, c: u64)->u64 => a * b - a * c

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func cancelProducts(a, b, c: u64)->u64 => a * (b + 1) - a * b

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func squareSum(a, b, c: u64)->u64 => (a + b) * (a + b)

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func xorOr(a, b, c: u64)->u64 => a ^ (a | b)

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func andXor(a, b, c: u64)->u64 => a & (a ^ b)

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func orMinusAnd(a, b, c: u64)->u64 => (a | b) - (a & b)

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func xorPlusCarry(a, b, c: u64)->u64 => (a ^ b) + ((a & b) << 1)

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func divideAndRemainder(a, b, c: u64)->u64 => a / 3 + a % 3

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func dynamicDivideRemainder(a, b, c: u64)->u64 => a / b + a % b

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func signedModuloTwo(a, b, c: s64)->s64 => a % 2

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func signedModuloEight(a, b, c: s64)->s64 => a % 8

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func signedModuloNegativeEight(a, b, c: s64)->s64 => a % -8

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func roundDownEight(a, b, c: u64)->u64 => (a >> 3) << 3

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func signedRoundDownEight(a, b, c: s64)->s64 => (a >> 3) << 3

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func shiftMasked(a, b, c: u64)->u64 => a << (b & 63)

