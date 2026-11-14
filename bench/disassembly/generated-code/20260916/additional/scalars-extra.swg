#global public

#[Swag.NoInline]
func zeroEq(a, b, c: u64)->u64 => a == 0 ? 1 : 0

#[Swag.NoInline]
func zeroNe(a, b, c: u64)->u64 => a != 0 ? 1 : 0

#[Swag.NoInline]
func lessTen(a, b, c: u64)->u64 => a < 10 ? 1 : 0

#[Swag.NoInline]
func atLeastTen(a, b, c: u64)->u64 => a >= 10 ? 1 : 0

#[Swag.NoInline]
func bitThree(a, b, c: u64)->u64 => (a & 8) != 0 ? 1 : 0

#[Swag.NoInline]
func wordHigh(a, b, c: u64)->u64 => (a >> 8) & 65535

#[Swag.NoInline]
func selectFiveThree(a, b, c: u64)->u64 => a < b ? 5 : 3

#[Swag.NoInline]
func selectNineOne(a, b, c: u64)->u64 => a < b ? 9 : 1

#[Swag.NoInline]
func selectSevenZero(a, b, c: u64)->u64 => a < b ? 7 : 0

#[Swag.NoInline]
func selectFourThree(a, b, c: u64)->u64 => a < b ? 4 : 3

#[Swag.NoInline]
func shiftOr(a, b, c: u64)->u64 => (a << 3) | (b << 3)

#[Swag.NoInline]
func shiftAnd(a, b, c: u64)->u64 => (a << 3) & (b << 3)

#[Swag.NoInline]
func shiftXor(a, b, c: u64)->u64 => (a << 3) ^ (b << 3)

#[Swag.NoInline]
func shiftAdd(a, b, c: u64)->u64 => (a << 3) + (b << 3)

#[Swag.NoInline]
func shiftSubtract(a, b, c: u64)->u64 => (a << 3) - (b << 3)

#[Swag.NoInline]
func rightOr(a, b, c: u64)->u64 => (a >> 5) | (b >> 5)

#[Swag.NoInline]
func rightAnd(a, b, c: u64)->u64 => (a >> 5) & (b >> 5)

#[Swag.NoInline]
func rightXor(a, b, c: u64)->u64 => (a >> 5) ^ (b >> 5)

#[Swag.NoInline]
func factorMultiply(a, b, c: u64)->u64 => a * 3 + b * 3

#[Swag.NoInline]
func signedDivideTwo(a, b, c: s64)->s64 => a / 2

#[Swag.NoInline]
func signedDivideThree(a, b, c: s64)->s64 => a / 3

#[Swag.NoInline]
func signedDivideSeven(a, b, c: s64)->s64 => a / 7

#[Swag.NoInline]
func signedModuloThree(a, b, c: s64)->s64 => a % 3

#[Swag.NoInline]
func signedNegative(a, b, c: s64)->s64 => a < 0 ? 1 : 0

#[Swag.NoInline]
func signedSelect(a, b, c: s64)->s64 => a < b ? -3 : 5

