#global fileprivate

// =============================================
// Safety flag configuration
// =============================================

#[Swag.Safety(.Overflow, false)]
func overflowSafetyDisabled()->bool
{
    return #safety(Swag.SafetyWhat.Overflow)
}

#[Swag.Safety(.Overflow, true)]
func overflowSafetyEnabled()->bool
{
    return #safety(Swag.SafetyWhat.Overflow)
}

#test
{
    const cfg      = #run dref @compiler.getBuildCfg()
    const expected = cfg.safetyGuards & Swag.SafetyWhat.Overflow ? true : false
    #assert(#safety(Swag.SafetyWhat.Overflow) == expected)
}

#test
{
    const value = #run overflowSafetyDisabled()
    #assert(value == false)
}

#test
{
    const value = #run overflowSafetyEnabled()
    #assert(value == true)
}

// =============================================
// Addition overflow — signed
// =============================================

#test
{
    #[Swag.Safety(.Overflow, true)]
    func addOverflowS8(a, b: s8)->s8
    {
        return a + b // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run addOverflowS8(127's8, 1's8)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func addOverflowS16(a, b: s16)->s16
    {
        return a + b // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run addOverflowS16(32767's16, 1's16)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func addOverflowS32(a, b: s32)->s32
    {
        return a + b // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run addOverflowS32(2147483647's32, 1's32)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func addOverflowS64(a, b: s64)->s64
    {
        return a + b // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run addOverflowS64(9223372036854775807's64, 1's64)
}

// Negative direction: MIN + (-1) underflows
#test
{
    #[Swag.Safety(.Overflow, true)]
    func addUnderflowS8(a, b: s8)->s8
    {
        return a + b // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run addUnderflowS8(-128's8, -1's8)
}

// =============================================
// Addition overflow — unsigned
// =============================================

#test
{
    #[Swag.Safety(.Overflow, true)]
    func addOverflowU8(a, b: u8)->u8
    {
        return a + b // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run addOverflowU8(255'u8, 1'u8)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func addOverflowU16(a, b: u16)->u16
    {
        return a + b // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run addOverflowU16(65535'u16, 1'u16)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func addOverflowU32(a, b: u32)->u32
    {
        return a + b // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run addOverflowU32(4294967295'u32, 1'u32)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func addOverflowU64(a, b: u64)->u64
    {
        return a + b // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run addOverflowU64(18446744073709551615'u64, 1'u64)
}

// =============================================
// Subtraction overflow — signed
// =============================================

#test
{
    #[Swag.Safety(.Overflow, true)]
    func subOverflowS8(a, b: s8)->s8
    {
        return a - b // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run subOverflowS8(-128's8, 1's8)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func subOverflowS16(a, b: s16)->s16
    {
        return a - b // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run subOverflowS16(-32768's16, 1's16)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func subOverflowS32(a, b: s32)->s32
    {
        return a - b // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run subOverflowS32(-2147483648's32, 1's32)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func subOverflowS64(a, b: s64)->s64
    {
        return a - b // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run subOverflowS64(-9223372036854775808's64, 1's64)
}

// Positive direction: MAX - (-1) overflows
#test
{
    #[Swag.Safety(.Overflow, true)]
    func subOverflowPosS8(a, b: s8)->s8
    {
        return a - b // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run subOverflowPosS8(127's8, -1's8)
}

// =============================================
// Subtraction overflow — unsigned
// =============================================

#test
{
    #[Swag.Safety(.Overflow, true)]
    func subOverflowU8(a, b: u8)->u8
    {
        return a - b // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run subOverflowU8(0'u8, 1'u8)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func subOverflowU16(a, b: u16)->u16
    {
        return a - b // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run subOverflowU16(0'u16, 1'u16)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func subOverflowU32(a, b: u32)->u32
    {
        return a - b // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run subOverflowU32(0'u32, 1'u32)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func subOverflowU64(a, b: u64)->u64
    {
        return a - b // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run subOverflowU64(0'u64, 1'u64)
}

// =============================================
// Multiplication overflow — signed
// =============================================

#test
{
    #[Swag.Safety(.Overflow, true)]
    func mulOverflowS16(a, b: s16)->s16
    {
        return a * b // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run mulOverflowS16(32767's16, 2's16)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func mulOverflowS32(a, b: s32)->s32
    {
        return a * b // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run mulOverflowS32(2147483647's32, 2's32)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func mulOverflowS64(a, b: s64)->s64
    {
        return a * b // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run mulOverflowS64(9223372036854775807's64, 2's64)
}

// =============================================
// Multiplication overflow — unsigned
// =============================================

#test
{
    #[Swag.Safety(.Overflow, true)]
    func mulOverflowU16(a, b: u16)->u16
    {
        return a * b // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run mulOverflowU16(32768'u16, 2'u16)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func mulOverflowU32(a, b: u32)->u32
    {
        return a * b // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run mulOverflowU32(2147483648'u32, 2'u32)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func mulOverflowU64(a, b: u64)->u64
    {
        return a * b // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run mulOverflowU64(9223372036854775808'u64, 2'u64)
}

// =============================================
// Division overflow — signed (MIN / -1)
// =============================================

#test
{
    #[Swag.Safety(.Overflow, true)]
    func divOverflowS8(a, b: s8)->s8
    {
        return a / b // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run divOverflowS8(-128's8, -1)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func divOverflowS16(a, b: s16)->s16
    {
        return a / b // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run divOverflowS16(-32768's16, -1)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func divOverflowS32(a, b: s32)->s32
    {
        return a / b // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run divOverflowS32(-2147483648's32, -1)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func divOverflowS64(a, b: s64)->s64
    {
        return a / b // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run divOverflowS64(-9223372036854775808's64, -1)
}

// =============================================
// Modulo overflow — signed (MIN % -1)
// =============================================

#test
{
    #[Swag.Safety(.Overflow, true)]
    func modOverflowS8(a, b: s8)->s8
    {
        return a % b // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run modOverflowS8(-128's8, -1)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func modOverflowS16(a, b: s16)->s16
    {
        return a % b // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run modOverflowS16(-32768's16, -1)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func modOverflowS32(a, b: s32)->s32
    {
        return a % b // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run modOverflowS32(-2147483648's32, -1)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func modOverflowS64(a, b: s64)->s64
    {
        return a % b // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run modOverflowS64(-9223372036854775808's64, -1)
}

// =============================================
// Unary negation overflow — signed (-MIN)
// =============================================

#test
{
    #[Swag.Safety(.Overflow, true)]
    func negOverflowS8(v: s8)->s8
    {
        return -v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run negOverflowS8(-128's8)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func negOverflowS16(v: s16)->s16
    {
        return -v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run negOverflowS16(-32768's16)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func negOverflowS32(v: s32)->s32
    {
        return -v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run negOverflowS32(-2147483648's32)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func negOverflowS64(v: s64)->s64
    {
        return -v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run negOverflowS64(-9223372036854775808's64)
}

// =============================================
// Shift left overflow (bit loss) — signed
// =============================================

#test
{
    #[Swag.Safety(.Overflow, true)]
    func shlOverflowS8(a, count: s8)->s8
    {
        return a << count // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run shlOverflowS8(64's8, 1's8)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func shlOverflowS16(a, count: s16)->s16
    {
        return a << count // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run shlOverflowS16(16384's16, 1's16)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func shlOverflowS32(a, count: s32)->s32
    {
        return a << count // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run shlOverflowS32(1073741824's32, 1's32)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func shlOverflowS64(a, count: s64)->s64
    {
        return a << count // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run shlOverflowS64(4611686018427387904's64, 1's64)
}

// =============================================
// Shift left overflow (bit loss) — unsigned
// =============================================

#test
{
    #[Swag.Safety(.Overflow, true)]
    func shlOverflowU8(a, count: u8)->u8
    {
        return a << count // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run shlOverflowU8(128'u8, 1'u8)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func shlOverflowU16(a, count: u16)->u16
    {
        return a << count // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run shlOverflowU16(32768'u16, 1'u16)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func shlOverflowU32(a, count: u32)->u32
    {
        return a << count // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run shlOverflowU32(2147483648'u32, 1'u32)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func shlOverflowU64(a, count: u64)->u64
    {
        return a << count // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run shlOverflowU64(9223372036854775808'u64, 1'u64)
}

// Shift left with count >= bit width (non-zero value triggers overflow)
#test
{
    #[Swag.Safety(.Overflow, true)]
    func shlLargeCountS8(a, count: s8)->s8
    {
        return a << count // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run shlLargeCountS8(1's8, 8's8)
}

// Shift left with count >= bit width and zero value: no overflow
#test
{
    #[Swag.Safety(.Overflow, true)]
    func shlLargeCountZero(a, count: u8)->u8
    {
        return a << count
    }

    const value = #run shlLargeCountZero(0'u8, 8'u8)
    @assert(value == 0'u8)
}

// =============================================
// Shift left — negative count
// =============================================

#test
{
    #[Swag.Safety(.Overflow, true)]
    func shlNegCountS8(a, count: s8)->s8
    {
        return a << count // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run shlNegCountS8(1's8, -1's8)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func shlNegCountS16(a, count: s16)->s16
    {
        return a << count // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run shlNegCountS16(1's16, -1's16)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func shlNegCountS32(a, count: s32)->s32
    {
        return a << count // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run shlNegCountS32(1's32, -1's32)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func shlNegCountS64(a, count: s64)->s64
    {
        return a << count // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run shlNegCountS64(1's64, -1's64)
}

// =============================================
// Shift right — negative count
// =============================================

#test
{
    #[Swag.Safety(.Overflow, true)]
    func shrNegCountS8(a, count: s8)->s8
    {
        return a >> count // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run shrNegCountS8(42's8, -1's8)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func shrNegCountS16(a, count: s16)->s16
    {
        return a >> count // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run shrNegCountS16(42's16, -1's16)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func shrNegCountS32(a, count: s32)->s32
    {
        return a >> count // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run shrNegCountS32(42's32, -1's32)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func shrNegCountS64(a, count: s64)->s64
    {
        return a >> count // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run shrNegCountS64(42's64, -1's64)
}

// =============================================
// Compound assignment overflow
// =============================================

#test
{
    #[Swag.Optimize(false), Swag.Safety(.Overflow, true)]
    func addAssignOverflowS8()->s8
    {
        var v: s8 = 127
        v += 1 // swc-expected-error {{safety_err_runtime}}
        return v
    }

    const value = #run addAssignOverflowS8()
}

#test
{
    #[Swag.Optimize(false), Swag.Safety(.Overflow, true)]
    func addAssignOverflowU8()->u8
    {
        var v: u8 = 255
        v += 1 // swc-expected-error {{safety_err_runtime}}
        return v
    }

    const value = #run addAssignOverflowU8()
}

#test
{
    #[Swag.Optimize(false), Swag.Safety(.Overflow, true)]
    func subAssignOverflowS16()->s16
    {
        var v: s16 = -32768
        v -= 1 // swc-expected-error {{safety_err_runtime}}
        return v
    }

    const value = #run subAssignOverflowS16()
}

#test
{
    #[Swag.Optimize(false), Swag.Safety(.Overflow, true)]
    func subAssignOverflowU16()->u16
    {
        var v: u16 = 0
        v -= 1 // swc-expected-error {{safety_err_runtime}}
        return v
    }

    const value = #run subAssignOverflowU16()
}

#test
{
    #[Swag.Optimize(false), Swag.Safety(.Overflow, true)]
    func mulAssignOverflowS32()->s32
    {
        var v: s32 = 2147483647
        v *= 2 // swc-expected-error {{safety_err_runtime}}
        return v
    }

    const value = #run mulAssignOverflowS32()
}

#test
{
    #[Swag.Optimize(false), Swag.Safety(.Overflow, true)]
    func mulAssignOverflowU32()->u32
    {
        var v: u32 = 2147483648
        v *= 2 // swc-expected-error {{safety_err_runtime}}
        return v
    }

    const value = #run mulAssignOverflowU32()
}

#test
{
    #[Swag.Optimize(false), Swag.Safety(.Overflow, true)]
    func divAssignOverflowS8()->s8
    {
        var v: s8 = -128
        v /= -1 // swc-expected-error {{safety_err_runtime}}
        return v
    }

    const value = #run divAssignOverflowS8()
}

#test
{
    #[Swag.Optimize(false), Swag.Safety(.Overflow, true)]
    func modAssignOverflowS16()->s16
    {
        var v: s16 = -32768
        v %= -1 // swc-expected-error {{safety_err_runtime}}
        return v
    }

    const value = #run modAssignOverflowS16()
}

#test
{
    #[Swag.Optimize(false), Swag.Safety(.Overflow, true)]
    func shlAssignOverflowS8()->s8
    {
        var v: s8 = 64
        v <<= 1 // swc-expected-error {{safety_err_runtime}}
        return v
    }

    const value = #run shlAssignOverflowS8()
}

#test
{
    #[Swag.Optimize(false), Swag.Safety(.Overflow, true)]
    func shlAssignOverflowU8()->u8
    {
        var v: u8 = 128
        v <<= 1 // swc-expected-error {{safety_err_runtime}}
        return v
    }

    const value = #run shlAssignOverflowU8()
}

#test
{
    #[Swag.Optimize(false), Swag.Safety(.Overflow, true)]
    func shrAssignNegCountS32()->s32
    {
        var v: s32 = 42
        v >>= -1 // swc-expected-error {{safety_err_runtime}}
        return v
    }

    const value = #run shrAssignNegCountS32()
}

// =============================================
// Narrowing int-to-int casts — signed to signed
// =============================================

#test
{
    #[Swag.Safety(.Overflow, true)]
    func castS16ToS8(v: s16)->s8
    {
        return cast(s8) v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run castS16ToS8(128's16)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func castS16ToS8Neg(v: s16)->s8
    {
        return cast(s8) v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run castS16ToS8Neg(-129's16)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func castS32ToS16(v: s32)->s16
    {
        return cast(s16) v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run castS32ToS16(32768's32)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func castS64ToS32(v: s64)->s32
    {
        return cast(s32) v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run castS64ToS32(2147483648's64)
}

// =============================================
// Narrowing int-to-int casts — unsigned to unsigned
// =============================================

#test
{
    #[Swag.Safety(.Overflow, true)]
    func castU16ToU8(v: u16)->u8
    {
        return cast(u8) v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run castU16ToU8(256'u16)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func castU32ToU16(v: u32)->u16
    {
        return cast(u16) v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run castU32ToU16(65536'u32)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func castU64ToU32(v: u64)->u32
    {
        return cast(u32) v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run castU64ToU32(4294967296'u64)
}

// =============================================
// Int casts — signed to unsigned (negative value)
// =============================================

#test
{
    #[Swag.Safety(.Overflow, true)]
    func castS8ToU8(v: s8)->u8
    {
        return cast(u8) v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run castS8ToU8(-1's8)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func castS16ToU16(v: s16)->u16
    {
        return cast(u16) v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run castS16ToU16(-1's16)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func castS32ToU32(v: s32)->u32
    {
        return cast(u32) v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run castS32ToU32(-1's32)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func castS64ToU64(v: s64)->u64
    {
        return cast(u64) v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run castS64ToU64(-1's64)
}

// =============================================
// Int casts — unsigned to signed (value too large)
// =============================================

#test
{
    #[Swag.Safety(.Overflow, true)]
    func castU8ToS8(v: u8)->s8
    {
        return cast(s8) v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run castU8ToS8(128'u8)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func castU16ToS16(v: u16)->s16
    {
        return cast(s16) v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run castU16ToS16(32768'u16)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func castU32ToS32(v: u32)->s32
    {
        return cast(s32) v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run castU32ToS32(2147483648'u32)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func castU64ToS64(v: u64)->s64
    {
        return cast(s64) v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run castU64ToS64(9223372036854775808'u64)
}

// =============================================
// Float-to-int cast overflow — f64 to signed
// =============================================

#test
{
    #[Swag.Safety(.Overflow, true)]
    func castF64ToS8(v: f64)->s8
    {
        return cast(s8) v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run castF64ToS8(128.0)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func castF64ToS8Neg(v: f64)->s8
    {
        return cast(s8) v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run castF64ToS8Neg(-129.0)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func castF64ToS16(v: f64)->s16
    {
        return cast(s16) v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run castF64ToS16(32768.0)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func castF64ToS32(v: f64)->s32
    {
        return cast(s32) v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run castF64ToS32(2147483648.0)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func castF64ToS64(v: f64)->s64
    {
        return cast(s64) v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run castF64ToS64(9223372036854775808.0)
}

// =============================================
// Float-to-int cast overflow — f64 to unsigned
// =============================================

#test
{
    #[Swag.Safety(.Overflow, true)]
    func castF64ToU8(v: f64)->u8
    {
        return cast(u8) v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run castF64ToU8(256.0)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func castF64ToU8Neg(v: f64)->u8
    {
        return cast(u8) v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run castF64ToU8Neg(-1.0)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func castF64ToU16(v: f64)->u16
    {
        return cast(u16) v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run castF64ToU16(65536.0)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func castF64ToU32(v: f64)->u32
    {
        return cast(u32) v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run castF64ToU32(4294967296.0)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func castF64ToU64(v: f64)->u64
    {
        return cast(u64) v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run castF64ToU64(18446744073709551616.0)
}

// =============================================
// Float-to-int cast overflow — f32
// =============================================

#test
{
    #[Swag.Safety(.Overflow, true)]
    func castF32ToS8(v: f32)->s8
    {
        return cast(s8) v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run castF32ToS8(128.0'f32)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func castF32ToU8(v: f32)->u8
    {
        return cast(u8) v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run castF32ToU8(256.0'f32)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func castF32ToS16(v: f32)->s16
    {
        return cast(s16) v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run castF32ToS16(32768.0'f32)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func castF32ToU16(v: f32)->u16
    {
        return cast(u16) v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run castF32ToU16(65536.0'f32)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func castF32ToS32(v: f32)->s32
    {
        return cast(s32) v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run castF32ToS32(2147483648.0'f32)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func castF32ToU32(v: f32)->u32
    {
        return cast(u32) v // swc-expected-error {{safety_err_runtime}}
    }

    const value = #run castF32ToU32(4294967296.0'f32)
}

// =============================================
// #wrap modifier — suppresses overflow
// =============================================

#test
{
    #[Swag.Safety(.Overflow, true)]
    func addWrapU8(a, b: u8)->u8
    {
        return a + #wrap b
    }

    const value = #run addWrapU8(255'u8, 1'u8)
    @assert(value == 0'u8)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func subWrapU8(a, b: u8)->u8
    {
        return a - #wrap b
    }

    const value = #run subWrapU8(0'u8, 1'u8)
    @assert(value == 255'u8)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func mulWrapU8(a, b: u8)->u8
    {
        return a * #wrap b
    }

    const value = #run mulWrapU8(128'u8, 2'u8)
    @assert(value == 0'u8)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func shlWrapU8(a, count: u8)->u8
    {
        return a << #wrap count
    }

    const value = #run shlWrapU8(1'u8, 8'u8)
    @assert(value == 0'u8)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func wrapCastU16ToU8(v: u16)->u8
    {
        return cast #wrap(u8) v
    }

    const value = #run wrapCastU16ToU8(257'u16)
    @assert(value == 1'u8)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func wrapCastS8ToU8(v: s8)->u8
    {
        return cast #wrap(u8) v
    }

    const value = #run wrapCastS8ToU8(-1's8)
    @assert(value == 255'u8)
}

// =============================================
// #prom modifier — promote to larger type
// =============================================

#test
{
    #[Swag.Safety(.Overflow, true)]
    func addPromS8(a, b: s8)->s32
    {
        return a + #prom b
    }

    const value = #run addPromS8(127's8, 1's8)
    @assert(value == 128)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func subPromS8(a, b: s8)->s32
    {
        return a - #prom b
    }

    const value = #run subPromS8(-128's8, 1's8)
    @assert(value == -129)
}

#test
{
    #[Swag.Safety(.Overflow, true)]
    func mulPromS8(a, b: s8)->s32
    {
        return a * #prom b
    }

    const value = #run mulPromS8(127's8, 2's8)
    @assert(value == 254)
}
