using u64 = unsigned long long;
using s64 = long long;
extern "C" {
__declspec(noinline) u64 zeroEq(u64 a, u64 b, u64 c) { return a == 0 ? 1 : 0; }
__declspec(noinline) u64 zeroNe(u64 a, u64 b, u64 c) { return a != 0 ? 1 : 0; }
__declspec(noinline) u64 lessTen(u64 a, u64 b, u64 c) { return a < 10 ? 1 : 0; }
__declspec(noinline) u64 atLeastTen(u64 a, u64 b, u64 c) { return a >= 10 ? 1 : 0; }
__declspec(noinline) u64 bitThree(u64 a, u64 b, u64 c) { return (a & 8) != 0 ? 1 : 0; }
__declspec(noinline) u64 wordHigh(u64 a, u64 b, u64 c) { return (a >> 8) & 65535; }
__declspec(noinline) u64 selectFiveThree(u64 a, u64 b, u64 c) { return a < b ? 5 : 3; }
__declspec(noinline) u64 selectNineOne(u64 a, u64 b, u64 c) { return a < b ? 9 : 1; }
__declspec(noinline) u64 selectSevenZero(u64 a, u64 b, u64 c) { return a < b ? 7 : 0; }
__declspec(noinline) u64 selectFourThree(u64 a, u64 b, u64 c) { return a < b ? 4 : 3; }
__declspec(noinline) u64 shiftOr(u64 a, u64 b, u64 c) { return (a << 3) | (b << 3); }
__declspec(noinline) u64 shiftAnd(u64 a, u64 b, u64 c) { return (a << 3) & (b << 3); }
__declspec(noinline) u64 shiftXor(u64 a, u64 b, u64 c) { return (a << 3) ^ (b << 3); }
__declspec(noinline) u64 shiftAdd(u64 a, u64 b, u64 c) { return (a << 3) + (b << 3); }
__declspec(noinline) u64 shiftSubtract(u64 a, u64 b, u64 c) { return (a << 3) - (b << 3); }
__declspec(noinline) u64 rightOr(u64 a, u64 b, u64 c) { return (a >> 5) | (b >> 5); }
__declspec(noinline) u64 rightAnd(u64 a, u64 b, u64 c) { return (a >> 5) & (b >> 5); }
__declspec(noinline) u64 rightXor(u64 a, u64 b, u64 c) { return (a >> 5) ^ (b >> 5); }
__declspec(noinline) u64 factorMultiply(u64 a, u64 b, u64 c) { return a * 3 + b * 3; }
__declspec(noinline) s64 signedDivideTwo(s64 a, s64 b, s64 c) { return a / 2; }
__declspec(noinline) s64 signedDivideThree(s64 a, s64 b, s64 c) { return a / 3; }
__declspec(noinline) s64 signedDivideSeven(s64 a, s64 b, s64 c) { return a / 7; }
__declspec(noinline) s64 signedModuloThree(s64 a, s64 b, s64 c) { return a % 3; }
__declspec(noinline) s64 signedNegative(s64 a, s64 b, s64 c) { return a < 0 ? 1 : 0; }
__declspec(noinline) s64 signedSelect(s64 a, s64 b, s64 c) { return a < b ? -3 : 5; }
}
