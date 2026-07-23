/*
    :LICENCE
    This code is based on the Go library (https://github.com/golang/go/blob/master/src/strconv/extfloat.go)
    The original code has been modified for Swag
    See LICENCE.md for the corresponding licence.
*/

#global namespace StrConv
#global #[Swag.CanOverflow(true)]

// A FloatExt represents an extended floating-point number, with more
// precision than a float64. It does not try to save bits: the
// number represented by the structure is mant*(2^exp), with a negative
// sign if neg is true.
struct FloatExt
{
    mant: u64
    exp:  s64
    neg:  bool
}

// Powers of ten taken from double-conversion library.
// https://code.google.com/p/double-conversion/
const firstPowerOfTen = -348
const stepPowerOfTen  = 8

var SmallPowersOfTen: [?] FloatExt = [
    {1'u64 << 63, -63, false},           // 1
    {0xA'u64 << 60, -60, false},         // 1e1
    {0x64'u64 << 57, -57, false},        // 1e2
    {0x3E8'u64 << 54, -54, false},       // 1e3
    {0x2710'u64 << 50, -50, false},      // 1e4
    {0x186A0'u64 << 47, -47, false},     // 1e5
    {0xF4240'u64 << 44, -44, false},     // 1e6
    {0x989680'u64 << 40, -40, false}]

var powersOfTen: [?] FloatExt = [
    {0xFA8FD5A0081C0288, -1220, false},     // 10^-348
    {0xBAAEE17FA23EBF76, -1193, false},     // 10^-340
    {0x8B16FB203055AC76, -1166, false},     // 10^-332
    {0xCF42894A5DCE35EA, -1140, false},     // 10^-324
    {0x9A6BB0AA55653B2D, -1113, false},     // 10^-316
    {0xE61ACF033D1A45DF, -1087, false},     // 10^-308
    {0xAB70FE17C79AC6CA, -1060, false},     // 10^-300
    {0xFF77B1FCBEBCDC4F, -1034, false},     // 10^-292
    {0xBE5691EF416BD60C, -1007, false},     // 10^-284
    {0x8DD01FAD907FFC3C, -980, false},      // 10^-276
    {0xD3515C2831559A83, -954, false},      // 10^-268
    {0x9D71AC8FADA6C9B5, -927, false},      // 10^-260
    {0xEA9C227723EE8BCB, -901, false},      // 10^-252
    {0xAECC49914078536D, -874, false},      // 10^-244
    {0x823C12795DB6CE57, -847, false},      // 10^-236
    {0xC21094364DFB5637, -821, false},      // 10^-228
    {0x9096EA6F3848984F, -794, false},      // 10^-220
    {0xD77485CB25823AC7, -768, false},      // 10^-212
    {0xA086CFCD97BF97F4, -741, false},      // 10^-204
    {0xEF340A98172AACE5, -715, false},      // 10^-196
    {0xB23867FB2A35B28E, -688, false},      // 10^-188
    {0x84C8D4DFD2C63F3B, -661, false},      // 10^-180
    {0xC5DD44271AD3CDBA, -635, false},      // 10^-172
    {0x936B9FCEBB25C996, -608, false},      // 10^-164
    {0xDBAC6C247D62A584, -582, false},      // 10^-156
    {0xA3AB66580D5FDAF6, -555, false},      // 10^-148
    {0xF3E2F893DEC3F126, -529, false},      // 10^-140
    {0xB5B5ADA8AAFF80B8, -502, false},      // 10^-132
    {0x87625F056C7C4A8B, -475, false},      // 10^-124
    {0xC9BCFF6034C13053, -449, false},      // 10^-116
    {0x964E858C91BA2655, -422, false},      // 10^-108
    {0xDFF9772470297EBD, -396, false},      // 10^-100
    {0xA6DFBD9FB8E5B88F, -369, false},      // 10^-92
    {0xF8A95FCF88747D94, -343, false},      // 10^-84
    {0xB94470938FA89BCF, -316, false},      // 10^-76
    {0x8A08F0F8BF0F156B, -289, false},      // 10^-68
    {0xCDB02555653131B6, -263, false},      // 10^-60
    {0x993FE2C6D07B7FAC, -236, false},      // 10^-52
    {0xE45C10C42A2B3B06, -210, false},      // 10^-44
    {0xAA242499697392D3, -183, false},      // 10^-36
    {0xFD87B5F28300CA0E, -157, false},      // 10^-28
    {0xBCE5086492111AEB, -130, false},      // 10^-20
    {0x8CBCCC096F5088CC, -103, false},      // 10^-12
    {0xD1B71758E219652C, -77, false},       // 10^-4
    {0x9C40000000000000, -50, false},       // 10^4
    {0xE8D4A51000000000, -24, false},       // 10^12
    {0xAD78EBC5AC620000, 3, false},         // 10^20
    {0x813F3978F8940984, 30, false},        // 10^28
    {0xC097CE7BC90715B3, 56, false},        // 10^36
    {0x8F7E32CE7BEA5C70, 83, false},        // 10^44
    {0xD5D238A4ABE98068, 109, false},       // 10^52
    {0x9F4F2726179A2245, 136, false},       // 10^60
    {0xED63A231D4C4FB27, 162, false},       // 10^68
    {0xB0DE65388CC8ADA8, 189, false},       // 10^76
    {0x83C7088E1AAB65DB, 216, false},       // 10^84
    {0xC45D1DF942711D9A, 242, false},       // 10^92
    {0x924D692CA61BE758, 269, false},       // 10^100
    {0xDA01EE641A708DEA, 295, false},       // 10^108
    {0xA26DA3999AEF774A, 322, false},       // 10^116
    {0xF209787BB47D6B85, 348, false},       // 10^124
    {0xB454E4A179DD1877, 375, false},       // 10^132
    {0x865B86925B9BC5C2, 402, false},       // 10^140
    {0xC83553C5C8965D3D, 428, false},       // 10^148
    {0x952AB45CFA97A0B3, 455, false},       // 10^156
    {0xDE469FBD99A05FE3, 481, false},       // 10^164
    {0xA59BC234DB398C25, 508, false},       // 10^172
    {0xF6C69A72A3989F5C, 534, false},       // 10^180
    {0xB7DCBF5354E9BECE, 561, false},       // 10^188
    {0x88FCF317F22241E2, 588, false},       // 10^196
    {0xCC20CE9BD35C78A5, 614, false},       // 10^204
    {0x98165AF37B2153DF, 641, false},       // 10^212
    {0xE2A0B5DC971F303A, 667, false},       // 10^220
    {0xA8D9D1535CE3B396, 694, false},       // 10^228
    {0xFB9B7CD9A4A7443C, 720, false},       // 10^236
    {0xBB764C4CA7A44410, 747, false},       // 10^244
    {0x8BAB8EEFB6409C1A, 774, false},       // 10^252
    {0xD01FEF10A657842C, 800, false},       // 10^260
    {0x9B10A4E5E9913129, 827, false},       // 10^268
    {0xE7109BFBA19C0C9D, 853, false},       // 10^276
    {0xAC2820D9623BF429, 880, false},       // 10^284
    {0x80444B5E7AA7CF85, 907, false},       // 10^292
    {0xBF21E44003ACDD2D, 933, false},       // 10^300
    {0x8E679C2F5E44FF8F, 960, false},       // 10^308
    {0xD433179D9C8CB841, 986, false},       // 10^316
    {0x9E19DB92B4E31BA9, 1013, false},      // 10^324
    {0xEB96BF6EBADF77D9, 1039, false},      // 10^332
    {0xAF87023B9BF0EE6B, 1066, false}]

impl FloatExt
{
    // AssignComputeBounds sets f to the floating point value
    // defined by mant, exp and precision given by flt. It returns
    // lower, upper such that any number in the closed interval
    // [lower, upper] is converted back to the same floating point number.
    mtd assignComputeBounds(mantp: u64, expp: s64, negp: bool)->{ lower: FloatExt, upper: FloatExt }
    {
        var result: retval

        .mant = mantp
        .exp  = expp - Swag.F64.MantBits
        .neg  = negp
        if .exp <= 0 and .mant == (.mant >> cast(u32) -.exp) << cast(u32) -.exp
        {
            // An exact integer
            .mant        >>= cast(u32) -.exp
            .exp         = 0
            result.lower = me
            result.upper = me
            return result
        }

        let expBiased = .exp - Swag.F64.Bias

        result.upper = FloatExt{2 * .mant + 1, .exp - 1, .neg}
        if .mant != 1'u64 << Swag.F64.MantBits or expBiased == 1 do
            result.lower = FloatExt{2 * .mant - 1, .exp - 1, .neg}
        else do
            result.lower = FloatExt{4 * .mant - 1, .exp - 2, .neg}
        return result
    }

    // Normalize normalizes f so that the highest bit of the mantissa is
    // set, and returns the number by which the mantissa was left-shifted.
    mtd normalize()
    {
        if .mant == 0 do
            return
        let shift = @bitcountlz(.mant)
        .mant <<= cast(u32) shift
        .exp  -= cast(s64) shift
    }

    // Multiply sets f to the product f*g: the result is correctly rounded,
    // but not normalized.
    mtd multiply(g: FloatExt)
    {
        let (hi, lo) = Math.mulU64(.mant, g.mant)
        .mant = hi + (lo >> 63)
        .exp  = .exp + g.exp + 64
    }

    const uint64pow10: [?] u64 = [
        1,
        10,
        100,
        1000,
        10000,
        100000,
        1000000,
        10000000,
        100000000,
        1000000000,
        10000000000,
        100000000000,
        1000000000000,
        10000000000000,
        100000000000000,
        1000000000000000,
        10000000000000000,
        100000000000000000,
        1000000000000000000,
        10000000000000000000]

    // Frexp10 is an analogue of Math.Frexp for decimal powers. It scales
    // f by an approximate power of ten 10^-exp, and returns exp10, so
    // that f*10^exp10 has the same value as the old f, up to an ulp,
    // as well as the index of 10^-exp in the powersOfTen table.
    mtd frexp10()->{ exp10: s64, index: s64 }
    {
        // The constants expMin and expMax constrain the final value of the
        // binary exponent of f. We want a small integral part in the result
        // because finding digits of an integer requires divisions, whereas
        // digits of the fractional part can be found by repeatedly multiplying
        // by 10.
        const expMin = -60
        const expMax = -32

        // Find power of ten such that x * 10^n has a binary exponent
        // between expMin and expMax.
        let approxExp10 = ((expMin + expMax) / 2 - .exp) * 28 / 93     // log(10)/log(2) is close to 93/28.
        var i           = (approxExp10 - firstPowerOfTen) / stepPowerOfTen
        #scope(Loop)
            for
        {
            let exp1 = .exp + powersOfTen[i].exp + 64
            switch
            {
            case exp1 < expMin:
                i += 1
            case exp1 > expMax:
                i -= 1
            default:
                break to Loop
            }
        }

        // Apply the desired decimal shift on f. It will have exponent
        // in the desired range. This is multiplication by 10^-exp10.
        .multiply(powersOfTen[i])

        var result: retval
        result.exp10 = -(firstPowerOfTen + i * stepPowerOfTen)
        result.index = i
        return result
    }

    // frexp10Many applies a common shift by a power of ten to a, b, c.
    func frexp10Many(a, b, c: *FloatExt)->s64
    {
        let (exp10, i) = c.frexp10()
        a.multiply(powersOfTen[i])
        b.multiply(powersOfTen[i])
        return exp10
    }

    // FixedDecimal stores in d the first n significant digits
    // of the decimal representation of f. It returns false
    // if it cannot be sure of the answer.
    mtd fixedDecimal(d: *DecimalSlice, n: s64)->bool
    {
        if .mant == 0
        {
            d.nd  = 0
            d.dp  = 0
            d.neg = .neg
            return true
        }

        // Multiply by an appropriate power of ten to have a reasonable
        // number to process.
        .normalize()
            let (exp10, ?) = .frexp10()

        let shift    = cast(u32) -.exp
        var integer  = cast(u32) (.mant >> shift)
        var fraction = .mant - (cast(u64) integer << shift)
        var e        = 1'u64     // e is the uncertainty we have on the mantissa of f.

        // Write exactly n digits to d.
        var needed        = n         // how many digits are left to write.
        var integerDigits = 0         // the number of decimal digits of integer.
        var pow10         = 1'u64     // the power of ten by which f was scaled.

        var pow = 1'u64
        for i in 20
        {
            if pow > cast(u64) integer
            {
                integerDigits = i
                break
            }

            pow *= 10
        }

        var rest = integer
        if integerDigits > needed
        {
            // the integral part is already large, trim the last digits.
            pow10   = uint64pow10[integerDigits - needed]
            integer /= cast(u32) pow10
            rest    -= integer * cast(u32) pow10
        }
        else do
            rest = 0

        // Write the digits of integer: the digits of rest are omitted.
        var buf: [32] u8
        var pos  = @countof(buf)

        var v = integer
        while v > 0
        {
            let v1 = v / 10
            v        -= 10 * v1
            pos      -= 1
            buf[pos] = cast(u8) (v + '0')
            v        = v1
        }

        for var i = pos; i < @countof(buf); i += 1 do
            d.d[i - pos] = buf[i]

        var nd = cast(s64) (@countof(buf) - pos)
        d.nd   = nd
        d.dp   = integerDigits + exp10
        needed -= nd

        if needed > 0
        {
            // Emit digits for the fractional part. Each time, 10*fraction
            // fits in a uint64 without overflow.
            while needed > 0
            {
                fraction *= 10
                e        *= 10     // the uncertainty scales as we multiply by ten.
                if 2 * e > (1 << shift)
                {
                    // the error is so large it could modify which digit to write, abort.
                    return false
                }

                let digit = fraction >> shift
                d.d[nd]  = cast(u8) (digit + '0')
                fraction -= digit << shift
                nd       += 1
                needed   -= 1
            }

            d.nd = nd
        }

        // We have written a truncation of f (a numerator / 10^d.dp). The remaining part
        // can be interpreted as a small number (< 1) to be added to the last digit of the
        // numerator.
        //
        // If rest > 0, the amount is:
        //    (rest<<shift | fraction) / (pow10 << shift)
        //    fraction being known with a ±e uncertainty.
        //    The fact that n > 0 guarantees that pow10 << shift does not overflow a uint64.
        //
        // If rest = 0, pow10 == 1 and the amount is
        //    fraction / (1 << shift)
        //    fraction being known with a ±e uncertainty.
        //
        // We pass this information to the rounding routine for adjustment.

        let ok = adjustLastDigitFixed(d, (cast(u64) rest << shift) | fraction, pow10, shift, e)
        if !ok do
            return false

        // Trim trailing zeros.
        for var i = d.nd - 1; i >= 0; i -= 1
        {
            if d.d[i] != '0'
            {
                d.nd = i + 1
                break
            }
        }

        return true
    }

    // adjustLastDigitFixed assumes d contains the representation of the integral part
    // of some number, whose fractional part is num / (den << shift). The numerator
    // num is only known up to an uncertainty of size e, assumed to be less than
    // (den << shift)/2.
    //
    // It will increase the last digit by one to account for correct rounding, typically
    // when the fractional part is greater than 1/2, and will return false if e is such
    // that no correct answer can be given.
    func adjustLastDigitFixed(d: *DecimalSlice, num, den: u64, shift: u32, e: u64)->bool
    {
        if 2 * (num + e) < (den << shift) do
            return true

        if 2 * (num - e) > (den << shift)
        {
            // increment d by 1.
            var i = d.nd - 1
            while i >= 0
            {
                if d.d[i] == '9' do
                    d.nd -= 1
                else do
                    break
                i -= 1
            }

            if i < 0
            {
                d.d[0] = '1'
                d.nd   = 1
                d.dp   += 1
            }
            else do
                d.d[i] += 1
            return true
        }

        return false
    }

    // ShortestDecimal stores in d the shortest decimal representation of f
    // which belongs to the open interval (lower, upper), where f is supposed
    // to lie. It returns false whenever the result is unsure. The implementation
    // uses the Grisu3 algorithm.
    mtd shortestDecimal(d: *DecimalSlice, lower, upper: *FloatExt)->bool
    {
        if .mant == 0
        {
            d.nd  = 0
            d.dp  = 0
            d.neg = .neg
            return true
        }

        if .exp == 0 and dref lower == dref &me and dref lower == dref upper
        {
            // an exact integer.
            var buf: [24] u8
            var n    = @countof(buf) - 1
            var v    = .mant
            while v > 0
            {
                let v1 = v / 10
                v      -= 10 * v1
                buf[n] = cast(u8) (v + '0')
                n      -= 1
                v      = v1
            }

            let nd = cast(s64) (@countof(buf) - n - 1)
            for var i = 0; i < nd; i += 1 do
                d.d[i] = buf[n + 1 + i]

            d.nd = nd
            d.dp = nd
            while d.nd > 0 and d.d[d.nd - 1] == '0' do
                d.nd -= 1

            if d.nd == 0 do
                d.dp = 0
            d.neg    = .neg
            return true
        }

        upper.normalize()

        // Uniformize exponents.
        if .exp > upper.exp
        {
            .mant <<= cast(u32) (.exp - upper.exp)
            .exp  = upper.exp
        }

        if lower.exp > upper.exp
        {
            lower.mant <<= cast(u32) (lower.exp - upper.exp)
            lower.exp  = upper.exp
        }

        let exp10 = frexp10Many(lower, me, upper)

        // Take a Safety margin due to rounding in frexp10Many, but we lose precision.
        upper.mant += 1
        lower.mant -= 1

        // The shortest representation of f is either rounded up or down, but
        // in any case, it is a truncation of upper.
        let shift    = cast(u32) -upper.exp
        var integer  = cast(u32) (upper.mant >> shift)
        var fraction = upper.mant - (cast(u64) integer << shift)

        // How far we can go down from upper until the result is wrong.
        let allowance = upper.mant - lower.mant

        // How far we should go to get a very precise result.
        let targetDiff = upper.mant - .mant

        // Count integral digits: there are at most 10.
        var integerDigits: s64
        var pow            = 1'u64
        for i in 20
        {
            if pow > cast(u64) integer
            {
                integerDigits = i
                break
            }

            pow *= 10
        }

        for i in integerDigits
        {
            pow = uint64pow10[integerDigits - i - 1]
            let digit = integer / cast(u32) pow
            d.d[i]  = cast(u8) (digit + '0')
            integer -= digit * cast(u32) pow

            // evaluate whether we should stop.
            let currentDiff = (cast(u64) integer << shift) + fraction
            if currentDiff < allowance
            {
                d.nd  = i + 1
                d.dp  = integerDigits + exp10
                d.neg = .neg

                // Sometimes allowance is so large the last digit might need to be
                // decremented to get closer to f.
                return adjustLastDigit(d, currentDiff, targetDiff, allowance, pow << shift, 2)
            }
        }

        d.nd  = integerDigits
        d.dp  = d.nd + exp10
        d.neg = .neg

        // Compute digits of the fractional part. At each step fraction does not
        // overflow. The choice of minExp implies that fraction is less than 2^60.
        var digit: s64
        var multiplier = 1'u64
        for
        {
            fraction   *= 10
            multiplier *= 10
            digit      = cast(s64) (fraction >> shift)
            d.d[d.nd]  = cast(u8) (digit + '0')
            d.nd       += 1
            fraction   -= cast(u64) digit << shift
            if fraction < allowance * multiplier
            {
                // We are in the admissible range. Note that if allowance is about to
                // overflow, that is, allowance > 2^64/10, the condition is automatically
                // true due to the limited range of fraction.
                return adjustLastDigit(d, fraction, targetDiff * multiplier, allowance * multiplier, 1'u64 << shift, multiplier * 2)
            }
        }

        return false
    }

    // adjustLastDigit modifies d = x-currentDiff*ε, to get closest to
    // d = x-targetDiff*ε, without becoming smaller than x-maxDiff*ε.
    // It assumes that a decimal digit is worth ulpDecimal*ε, and that
    // all data is known with an error estimate of ulpBinary*ε.
    func adjustLastDigit(d: *DecimalSlice, cdiff, targetDiff, maxDiff, ulpDecimal, ulpBinary: u64)->bool
    {
        var currentDiff = cdiff

        // Approximation is too wide.
        if ulpDecimal < 2 * ulpBinary do
            return false

        while currentDiff + (ulpDecimal / 2) + ulpBinary < targetDiff
        {
            d.d[d.nd - 1] -= 1
            currentDiff   += ulpDecimal
        }

        // we have two choices, and don't know what to:.
        if currentDiff + ulpDecimal <= targetDiff + (ulpDecimal / 2) + ulpBinary do
            return false

        // we went too far
        if currentDiff < ulpBinary or currentDiff > maxDiff - ulpBinary do
            return false

        // the number has actually reached zero.
        if d.nd == 1 and d.d[0] == '0'
        {
            d.nd = 0
            d.dp = 0
        }

        return true
    }
}
