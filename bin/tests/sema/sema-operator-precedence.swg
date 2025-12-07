#assert(1 + 2 * 3 == 7)
#assert(1 * 2 + 3 == 5)
#assert(4 + 10 / 2 == 9)
#assert(4 * 10 - 2 == 38)
#assert(10 - 3 * 2 == 4)
#assert(10 / 5 + 6 == 8)
#assert(10 % 4 + 1 == 3)
#assert(10 - 8 / 2 == 6)
#assert(1 + 2 << 3 == (1 + 2) << 3)   // (3 << 3) == 24
#assert(1 * 2 << 3 == (1 * 2) << 3)   // (2 << 3) == 16
#assert(1 << 2 + 3 == 1 << (2 + 3))   // 1 << 5 == 32
#assert(8 >> 1 + 1 == 8 >> (1 + 1))   // 8 >> 2 == 2
#assert(1 + 2 << 3 == 24)
#assert(1 * 2 << 3 == 16)
#assert(1 << 2 + 3 == 32)
#assert(8 >> 1 + 1 == 2)
#assert(1 | 2 & 3 == 1 | (2 & 3))     // 1 | 2 == 3
#assert(1 ^ 2 & 3 == 1 ^ (2 & 3))     // 1 ^ 2 == 3
#assert(4 & 3 << 1 == 4 & (3 << 1))   // 4 & 6 == 4
#assert(8 | 2 << 1 == 8 | (2 << 1))   // 8 | 4 == 12
#assert(1 | 2 & 3 == 3)
#assert(1 ^ 2 & 3 == 3)
#assert(4 & 3 << 1 == 4)
#assert(8 | 2 << 1 == 12)
#assert(-1 + 2 * 3 == 5)     // -(1) + 6 == 5
#assert(~1 & 3 == (~1) & 3)  // (~1) = -2, -2 & 3 == 2
#assert(1 + 2 * 3 << 2 == (1 + (2 * 3)) << 2)   // (1+6)<<2 = 7<<2 = 28
#assert(8 >> 1 + 2 * 1 == 8 >> (1 + 2))         // 8 >> 3 = 1
#assert(1 | 2 ^ 3 & 4 == 1 | (2 ^ (3 & 4)))     // 3 ^ 4 == 7 → 1|0 == 1

#assert(1 < 2 == true)
#assert((1 < 2) == true)
#assert(1 == 1 < 2)         // swc-expected-error {{sema_err_compare_operand_type}}
#assert((1 == 1) < 2)       // swc-expected-error {{sema_err_compare_operand_type}}