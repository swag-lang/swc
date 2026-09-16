using u64 = unsigned long long;
using s64 = long long;
using u32 = unsigned int;
using s32 = int;
extern "C" {
__declspec(noinline) s64 negativeDivideTwo(s64 a, s64 b, s64 c) { return a / -2; }
__declspec(noinline) s64 negativeDivideEight(s64 a, s64 b, s64 c) { return a / -8; }
__declspec(noinline) s64 negativeDivideThree(s64 a, s64 b, s64 c) { return a / -3; }
__declspec(noinline) s64 negativeModuloTwo(s64 a, s64 b, s64 c) { return a % -2; }
__declspec(noinline) u64 clearLowestBit(u64 a, u64 b, u64 c) { return a & (a - 1); }
__declspec(noinline) u64 isolateLowestBit(u64 a, u64 b, u64 c) { return a & (0 - a); }
__declspec(noinline) u64 andNot(u64 a, u64 b, u64 c) { return a & ~b; }
__declspec(noinline) u64 negatedSum(u64 a, u64 b, u64 c) { return (0 - a) + (0 - b); }
__declspec(noinline) u64 complementSum(u64 a, u64 b, u64 c) { return ~(~a + b); }
__declspec(noinline) u64 unsignedAverage(u64 a, u64 b, u64 c) { return (a & b) + ((a ^ b) >> 1); }
__declspec(noinline) u64 variableBit(u64 a, u64 b, u64 c) { return (a >> (b & 63)) & 1; }
__declspec(noinline) u64 maskedShiftRight(u64 a, u64 b, u64 c) { return a >> (b & 63); }
__declspec(noinline) s64 maskedArithmeticRight(s64 a, s64 b, s64 c) { return a >> (b & 63); }
__declspec(noinline) u64 rotateVariable(u64 a, u64 b, u64 c) { return (a << (b & 63)) | (a >> ((0 - b) & 63)); }
__declspec(noinline) u32 add32(u32 a, u32 b, u32 c) { return a + b; }
__declspec(noinline) u32 multiply32(u32 a, u32 b, u32 c) { return a * b; }
__declspec(noinline) u32 factor32(u32 a, u32 b, u32 c) { return a * b + a * c; }
__declspec(noinline) u32 square32(u32 a, u32 b, u32 c) { return (a + b) * (a + b); }
__declspec(noinline) u32 xorOr32(u32 a, u32 b, u32 c) { return a ^ (a | b); }
__declspec(noinline) u32 andXor32(u32 a, u32 b, u32 c) { return a & (a ^ b); }
__declspec(noinline) u32 orMinusAnd32(u32 a, u32 b, u32 c) { return (a | b) - (a & b); }
__declspec(noinline) u32 shiftMasked32(u32 a, u32 b, u32 c) { return a << (b & 31); }
__declspec(noinline) u32 rotate32(u32 a, u32 b, u32 c) { return (a << 7) | (a >> 25); }
__declspec(noinline) u32 extractByte32(u32 a, u32 b, u32 c) { return (a >> 8) & 255; }
__declspec(noinline) s32 signedModulo32(s32 a, s32 b, s32 c) { return a % 8; }
__declspec(noinline) s32 signedDivide32(s32 a, s32 b, s32 c) { return a / 7; }
__declspec(noinline) u32 unsignedDivide32(u32 a, u32 b, u32 c) { return a / 7; }
__declspec(noinline) u32 unsignedModulo32(u32 a, u32 b, u32 c) { return a % 7; }
__declspec(noinline) u32 zeroMask32(u32 a, u32 b, u32 c) { return a == 0 ? 0xFFFFFFFF : 0; }
__declspec(noinline) u32 nonzeroMask32(u32 a, u32 b, u32 c) { return a != 0 ? 0xFFFFFFFF : 0; }
__declspec(noinline) u32 selectSeven32(u32 a, u32 b, u32 c) { return a < b ? 7 : 0; }
__declspec(noinline) u32 subtractFlag32(u32 a, u32 b, u32 c) { return a - (b < c ? 1U : 0); }
}
