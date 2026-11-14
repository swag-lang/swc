#global public

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func negativeDivideTwo(a, b, c: s64)->s64 => a / -2

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func negativeDivideEight(a, b, c: s64)->s64 => a / -8

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func negativeDivideThree(a, b, c: s64)->s64 => a / -3

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func negativeModuloTwo(a, b, c: s64)->s64 => a % -2

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func clearLowestBit(a, b, c: u64)->u64 => a & (a - 1)

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func isolateLowestBit(a, b, c: u64)->u64 => a & (0 - a)

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func andNot(a, b, c: u64)->u64 => a & ~b

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func negatedSum(a, b, c: u64)->u64 => (0 - a) + (0 - b)

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func complementSum(a, b, c: u64)->u64 => ~(~a + b)

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func unsignedAverage(a, b, c: u64)->u64 => (a & b) + ((a ^ b) >> 1)

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func variableBit(a, b, c: u64)->u64 => (a >> (b & 63)) & 1

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func maskedShiftRight(a, b, c: u64)->u64 => a >> (b & 63)

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func maskedArithmeticRight(a, b, c: s64)->s64 => a >> (b & 63)

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func rotateVariable(a, b, c: u64)->u64 => (a << (b & 63)) | (a >> ((0 - b) & 63))

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func add32(a, b, c: u32)->u32 => a + b

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func multiply32(a, b, c: u32)->u32 => a * b

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func factor32(a, b, c: u32)->u32 => a * b + a * c

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func square32(a, b, c: u32)->u32 => (a + b) * (a + b)

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func xorOr32(a, b, c: u32)->u32 => a ^ (a | b)

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func andXor32(a, b, c: u32)->u32 => a & (a ^ b)

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func orMinusAnd32(a, b, c: u32)->u32 => (a | b) - (a & b)

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func shiftMasked32(a, b, c: u32)->u32 => a << (b & 31)

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func rotate32(a, b, c: u32)->u32 => (a << 7) | (a >> 25)

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func extractByte32(a, b, c: u32)->u32 => (a >> 8) & 255

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func signedModulo32(a, b, c: s32)->s32 => a % 8

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func signedDivide32(a, b, c: s32)->s32 => a / 7

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func unsignedDivide32(a, b, c: u32)->u32 => a / 7

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func unsignedModulo32(a, b, c: u32)->u32 => a % 7

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func zeroMask32(a, b, c: u32)->u32 => a == 0 ? 0xFFFFFFFF : 0

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func nonzeroMask32(a, b, c: u32)->u32 => a != 0 ? 0xFFFFFFFF : 0

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func selectSeven32(a, b, c: u32)->u32 => a < b ? 7 : 0

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func subtractFlag32(a, b, c: u32)->u32 => a - (b < c ? 1'u32 : 0)
