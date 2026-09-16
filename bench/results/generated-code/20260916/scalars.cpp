using u64 = unsigned long long;
extern "C" {
__declspec(noinline) u64 factorOr(u64 a, u64 b, u64 c) { return (a & b) | (a & c); }
__declspec(noinline) u64 factorAnd(u64 a, u64 b, u64 c) { return (a | b) & (a | c); }
__declspec(noinline) u64 absorbOr(u64 a, u64 b, u64 c) { return a | (a & b); }
__declspec(noinline) u64 absorbAnd(u64 a, u64 b, u64 c) { return a & (a | b); }
__declspec(noinline) u64 cancelXor(u64 a, u64 b, u64 c) { return (a ^ b) ^ a; }
__declspec(noinline) u64 cancelSub(u64 a, u64 b, u64 c) { return (a + b) - a; }
__declspec(noinline) u64 maskedShift(u64 a, u64 b, u64 c) { return (a & 255) << 8; }
__declspec(noinline) u64 shiftMask(u64 a, u64 b, u64 c) { return (a << 8) & 65280; }
__declspec(noinline) u64 shiftPair(u64 a, u64 b, u64 c) { return (a << 8) >> 8; }
__declspec(noinline) u64 notXor(u64 a, u64 b, u64 c) { return ~a ^ ~b; }
__declspec(noinline) u64 mergeMasks(u64 a, u64 b, u64 c) { return (a & 255) | (a & 65280); }
__declspec(noinline) u64 blend(u64 a, u64 b, u64 c) { return (a & c) | (b & ~c); }
__declspec(noinline) u64 mul7(u64 a, u64 b, u64 c) { return a * 7; }
__declspec(noinline) u64 mul10(u64 a, u64 b, u64 c) { return a * 10; }
__declspec(noinline) u64 mul12(u64 a, u64 b, u64 c) { return a * 12; }
__declspec(noinline) u64 mul15(u64 a, u64 b, u64 c) { return a * 15; }
__declspec(noinline) u64 mul17(u64 a, u64 b, u64 c) { return a * 17; }
__declspec(noinline) u64 div7(u64 a, u64 b, u64 c) { return a / 7; }
__declspec(noinline) u64 mod7(u64 a, u64 b, u64 c) { return a % 7; }
__declspec(noinline) u64 boolMask(u64 a, u64 b, u64 c) { return a < b ? 0xFFFFFFFFFFFFFFFF : 0; }
__declspec(noinline) u64 doubleAdd(u64 a, u64 b, u64 c) { return a + a; }
__declspec(noinline) u64 scaleThree(u64 a, u64 b, u64 c) { return a * 3; }
__declspec(noinline) u64 scaleFive(u64 a, u64 b, u64 c) { return a * 5; }
__declspec(noinline) u64 scaleNine(u64 a, u64 b, u64 c) { return a * 9; }
__declspec(noinline) u64 scaleThenAdd(u64 a, u64 b, u64 c) { return a * 5 + b; }
__declspec(noinline) u64 shiftThenAdd(u64 a, u64 b, u64 c) { return (a << 3) + b; }
__declspec(noinline) u64 sumThenDouble(u64 a, u64 b, u64 c) { return (a + b) << 1; }
__declspec(noinline) u64 maskThenAdd(u64 a, u64 b, u64 c) { return (a & 255) + (b & 255); }
__declspec(noinline) u64 highByte(u64 a, u64 b, u64 c) { return (a >> 8) & 255; }
__declspec(noinline) u64 wordShift(u64 a, u64 b, u64 c) { return (a & 65535) << 16; }
__declspec(noinline) u64 shiftMask24(u64 a, u64 b, u64 c) { return (a << 8) & 16776960; }
__declspec(noinline) u64 shiftMaskTop(u64 a, u64 b, u64 c) { return (a << 48) & 0xFFFF000000000000; }
__declspec(noinline) u64 rotate13(u64 a, u64 b, u64 c) { return (a << 13) | (a >> 51); }
__declspec(noinline) u64 complementOr(u64 a, u64 b, u64 c) { return ~(a | b); }
__declspec(noinline) u64 complementAnd(u64 a, u64 b, u64 c) { return ~(a & b); }
__declspec(noinline) u64 xorNot(u64 a, u64 b, u64 c) { return a ^ ~b; }
__declspec(noinline) u64 addNeg(u64 a, u64 b, u64 c) { return a + (~b + 1); }
__declspec(noinline) u64 minusNeg(u64 a, u64 b, u64 c) { return a - (~b + 1); }
__declspec(noinline) u64 mulNegOne(u64 a, u64 b, u64 c) { return a * 0xFFFFFFFFFFFFFFFF; }
__declspec(noinline) u64 lowPowerTest(u64 a, u64 b, u64 c) { return (a & 255) == 0 ? 1 : 0; }
__declspec(noinline) u64 flagPower(u64 a, u64 b, u64 c) { return a < b ? 256 : 0; }
__declspec(noinline) u64 flagLarge(u64 a, u64 b, u64 c) { return a < b ? 0x100000000 : 0; }
__declspec(noinline) u64 flagAdd(u64 a, u64 b, u64 c) { return (a < b ? 1 : 0) + c; }
__declspec(noinline) u64 minValue(u64 a, u64 b, u64 c) { return a < b ? a : b; }
__declspec(noinline) u64 maxValue(u64 a, u64 b, u64 c) { return a > b ? a : b; }
__declspec(noinline) u64 minZero(u64 a, u64 b, u64 c) { return a < 128 ? a : 0; }
__declspec(noinline) u64 differenceZero(u64 a, u64 b, u64 c) { return a - b == 0 ? 1 : 0; }
__declspec(noinline) u64 divideThree(u64 a, u64 b, u64 c) { return a / 3; }
__declspec(noinline) u64 moduloThree(u64 a, u64 b, u64 c) { return a % 3; }
__declspec(noinline) u64 divideTen(u64 a, u64 b, u64 c) { return a / 10; }
__declspec(noinline) u64 moduloTen(u64 a, u64 b, u64 c) { return a % 10; }
}
