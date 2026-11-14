#global public

#[Swag.NoInline]
func factorOr(a, b, c: u64)->u64 => (a & b) | (a & c)

#[Swag.NoInline]
func factorAnd(a, b, c: u64)->u64 => (a | b) & (a | c)

#[Swag.NoInline]
func absorbOr(a, b, c: u64)->u64 => a | (a & b)

#[Swag.NoInline]
func absorbAnd(a, b, c: u64)->u64 => a & (a | b)

#[Swag.NoInline]
func cancelXor(a, b, c: u64)->u64 => (a ^ b) ^ a

#[Swag.NoInline]
func cancelSub(a, b, c: u64)->u64 => (a + b) - a

#[Swag.NoInline]
func maskedShift(a, b, c: u64)->u64 => (a & 255) << 8

#[Swag.NoInline]
func shiftMask(a, b, c: u64)->u64 => (a << 8) & 65280

#[Swag.NoInline]
func shiftPair(a, b, c: u64)->u64 => (a << 8) >> 8

#[Swag.NoInline]
func notXor(a, b, c: u64)->u64 => ~a ^ ~b

#[Swag.NoInline]
func mergeMasks(a, b, c: u64)->u64 => (a & 255) | (a & 65280)

#[Swag.NoInline]
func blend(a, b, c: u64)->u64 => (a & c) | (b & ~c)

#[Swag.NoInline]
func mul7(a, b, c: u64)->u64 => a * 7

#[Swag.NoInline]
func mul10(a, b, c: u64)->u64 => a * 10

#[Swag.NoInline]
func mul12(a, b, c: u64)->u64 => a * 12

#[Swag.NoInline]
func mul15(a, b, c: u64)->u64 => a * 15

#[Swag.NoInline]
func mul17(a, b, c: u64)->u64 => a * 17

#[Swag.NoInline]
func div7(a, b, c: u64)->u64 => a / 7

#[Swag.NoInline]
func mod7(a, b, c: u64)->u64 => a % 7

#[Swag.NoInline]
func boolMask(a, b, c: u64)->u64 => a < b ? 0xFFFFFFFFFFFFFFFF : 0

#[Swag.NoInline]
func doubleAdd(a, b, c: u64)->u64 => a + a

#[Swag.NoInline]
func scaleThree(a, b, c: u64)->u64 => a * 3

#[Swag.NoInline]
func scaleFive(a, b, c: u64)->u64 => a * 5

#[Swag.NoInline]
func scaleNine(a, b, c: u64)->u64 => a * 9

#[Swag.NoInline]
func scaleThenAdd(a, b, c: u64)->u64 => a * 5 + b

#[Swag.NoInline]
func shiftThenAdd(a, b, c: u64)->u64 => (a << 3) + b

#[Swag.NoInline]
func sumThenDouble(a, b, c: u64)->u64 => (a + b) << 1

#[Swag.NoInline]
func maskThenAdd(a, b, c: u64)->u64 => (a & 255) + (b & 255)

#[Swag.NoInline]
func highByte(a, b, c: u64)->u64 => (a >> 8) & 255

#[Swag.NoInline]
func wordShift(a, b, c: u64)->u64 => (a & 65535) << 16

#[Swag.NoInline]
func shiftMask24(a, b, c: u64)->u64 => (a << 8) & 16776960

#[Swag.NoInline]
func shiftMaskTop(a, b, c: u64)->u64 => (a << 48) & 0xFFFF000000000000

#[Swag.NoInline]
func rotate13(a, b, c: u64)->u64 => (a << 13) | (a >> 51)

#[Swag.NoInline]
func complementOr(a, b, c: u64)->u64 => ~(a | b)

#[Swag.NoInline]
func complementAnd(a, b, c: u64)->u64 => ~(a & b)

#[Swag.NoInline]
func xorNot(a, b, c: u64)->u64 => a ^ ~b

#[Swag.NoInline]
func addNeg(a, b, c: u64)->u64 => a + (~b + 1)

#[Swag.NoInline]
func minusNeg(a, b, c: u64)->u64 => a - (~b + 1)

#[Swag.NoInline]
func mulNegOne(a, b, c: u64)->u64 => a * 0xFFFFFFFFFFFFFFFF

#[Swag.NoInline]
func lowPowerTest(a, b, c: u64)->u64 => (a & 255) == 0 ? 1 : 0

#[Swag.NoInline]
func flagPower(a, b, c: u64)->u64 => a < b ? 256 : 0

#[Swag.NoInline]
func flagLarge(a, b, c: u64)->u64 => a < b ? 0x100000000 : 0

#[Swag.NoInline]
func flagAdd(a, b, c: u64)->u64 => (a < b ? 1 : 0) + c

#[Swag.NoInline]
func minValue(a, b, c: u64)->u64 => a < b ? a : b

#[Swag.NoInline]
func maxValue(a, b, c: u64)->u64 => a > b ? a : b

#[Swag.NoInline]
func minZero(a, b, c: u64)->u64 => a < 128 ? a : 0

#[Swag.NoInline]
func differenceZero(a, b, c: u64)->u64 => a - b == 0 ? 1 : 0

#[Swag.NoInline]
func divideThree(a, b, c: u64)->u64 => a / 3

#[Swag.NoInline]
func moduloThree(a, b, c: u64)->u64 => a % 3

#[Swag.NoInline]
func divideTen(a, b, c: u64)->u64 => a / 10

#[Swag.NoInline]
func moduloTen(a, b, c: u64)->u64 => a % 10
