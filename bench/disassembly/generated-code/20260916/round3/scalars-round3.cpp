using u64 = unsigned long long;
using s64 = long long;
extern "C" {
__declspec(noinline) u64 minUnsigned(u64 a, u64 b, u64 c) { return a < b ? a : b; }
__declspec(noinline) u64 maxUnsigned(u64 a, u64 b, u64 c) { return a > b ? a : b; }
__declspec(noinline) s64 minSigned(s64 a, s64 b, s64 c) { return a < b ? a : b; }
__declspec(noinline) s64 maxSigned(s64 a, s64 b, s64 c) { return a > b ? a : b; }
__declspec(noinline) u64 clampUnsigned(u64 a, u64 b, u64 c) { return a > 100 ? 100 : a; }
__declspec(noinline) s64 clampSigned(s64 a, s64 b, s64 c) { return a < -10 ? -10 : a > 10 ? 10 : a; }
__declspec(noinline) u64 absSigned(s64 a, s64 b, s64 c) { return a < 0 ? 0ULL - (u64)a : (u64)a; }
__declspec(noinline) u64 zeroSelect(u64 a, u64 b, u64 c) { return a == 0 ? b : c; }
__declspec(noinline) u64 bitSelect(u64 a, u64 b, u64 c) { return (a & 1) != 0 ? b : c; }
__declspec(noinline) u64 bitTimesValue(u64 a, u64 b, u64 c) { return (a & 1) * b; }
__declspec(noinline) u64 addIfZero(u64 a, u64 b, u64 c) { return a + (b == 0 ? 1 : 0); }
__declspec(noinline) u64 addIfNotZero(u64 a, u64 b, u64 c) { return a + (b != 0 ? 1 : 0); }
__declspec(noinline) u64 subtractIfBelow(u64 a, u64 b, u64 c) { return a - (b < c ? 1 : 0); }
__declspec(noinline) u64 addIfAboveEqual(u64 a, u64 b, u64 c) { return a + (b >= c ? 1 : 0); }
__declspec(noinline) u64 equalMask(u64 a, u64 b, u64 c) { return a == 0 ? ~0ULL : 0; }
__declspec(noinline) u64 notEqualMask(u64 a, u64 b, u64 c) { return a != 0 ? ~0ULL : 0; }
__declspec(noinline) u64 factorProducts(u64 a, u64 b, u64 c) { return a * b + a * c; }
__declspec(noinline) u64 subtractProducts(u64 a, u64 b, u64 c) { return a * b - a * c; }
__declspec(noinline) u64 cancelProducts(u64 a, u64 b, u64 c) { return a * (b + 1) - a * b; }
__declspec(noinline) u64 squareSum(u64 a, u64 b, u64 c) { return (a + b) * (a + b); }
__declspec(noinline) u64 xorOr(u64 a, u64 b, u64 c) { return a ^ (a | b); }
__declspec(noinline) u64 andXor(u64 a, u64 b, u64 c) { return a & (a ^ b); }
__declspec(noinline) u64 orMinusAnd(u64 a, u64 b, u64 c) { return (a | b) - (a & b); }
__declspec(noinline) u64 xorPlusCarry(u64 a, u64 b, u64 c) { return (a ^ b) + ((a & b) << 1); }
__declspec(noinline) u64 divideAndRemainder(u64 a, u64 b, u64 c) { return a / 3 + a % 3; }
__declspec(noinline) u64 dynamicDivideRemainder(u64 a, u64 b, u64 c) { return a / b + a % b; }
__declspec(noinline) s64 signedModuloTwo(s64 a, s64 b, s64 c) { return a % 2; }
__declspec(noinline) s64 signedModuloEight(s64 a, s64 b, s64 c) { return a % 8; }
__declspec(noinline) s64 signedModuloNegativeEight(s64 a, s64 b, s64 c) { return a % -8; }
__declspec(noinline) u64 roundDownEight(u64 a, u64 b, u64 c) { return (a >> 3) << 3; }
__declspec(noinline) s64 signedRoundDownEight(s64 a, s64 b, s64 c) { return (s64)((u64)(a >> 3) << 3); }
__declspec(noinline) u64 shiftMasked(u64 a, u64 b, u64 c) { return a << (b & 63); }
}
