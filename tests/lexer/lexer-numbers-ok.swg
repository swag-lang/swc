// ============================================================================
// Lexer Numbers Ok
// ============================================================================

// swc-option lex-only

// --- Valid simple cases ---
0b0
0b1
0b00
0b01
0b10
0b11
0b0000
0b1111
0b00001111
0b10101010
0b11110000
0b01010101

// --- Valid with single underscore separators ---
0b1_0
0b0_1
0b1010_0101
0b1111_0000
0b0_0
0b1_1
0b1100_1100_1010_1010
0b11_00_11_00
0b_1
0b_0
0b_1010
0b_1_0_1_0

// --- Valid with long sequences ---
0b1010_1010_1010_1010
0b1111_0000_1111_0000
0b0000_1111_0000_1111
0b1100_1100_1100_1100
0b0011_0011_0011_0011
0b10101010_10101010_10101010_10101010

// --- 8-bit patterns (common byte values) ---
0b0000_0000
0b1111_1111
0b1010_1010
0b0101_0101
0b1100_0011
0b0011_1100

// --- 16-bit patterns ---
0b1111_1111_0000_0000
0b0000_0000_1111_1111
0b1010_1010_0101_0101

// --- Valid simple integers ---
0
1
9
10
42
123
999
1000
123456789

// --- Valid with single underscore separators ---
1_000
10_000
100_000
1_000_000
123_456_789
1_2_3
99_99_99

// --- Valid floats with decimal point ---
0.0
1.0
0.5
3.14
123.456
0.123456789
999.999
1000.0

// --- Valid floats with separators ---
1_000.0
1_234.567_89
1.234_567
0.123_456
1_000_000.999_999

// --- Valid with exponents (lowercase e) ---
1e10
1e+10
1e-10
0e0
123e5
1.23e4
0.5e-3

// --- Valid with exponents (uppercase E) ---
1E10
1E+10
1E-10
0E0
123E5
1.23E4
0.5E-3

// --- Valid exponents with separators ---
1_000e10
1_234.567e-5
1.234_567e+10

// --- Combined: float with exponent ---
3.14e2
2.718e-1
1.23e+10
0.001e3
123.456e-2
1_234.567_89e+5

// --- Range operator disambiguation ---
1..10       // Number '1' followed by range operator '..'
10..20      // Number '10' followed by range operator '..'
0..100      // Number '0' followed by range operator '..'
1.0..2.0    // Float '1.0' followed by range operator '..'

// --- Edge cases with zeros ---
0
00
000
0.0
0.00
0.000
0e0
0.0e0
0_0
0_0_0

// --- Large numbers with separators ---
1_000_000_000
9_999_999_999
1_234_567_890_123

// --- Small decimals ---
0.1
0.01
0.001
0.0001
0.00001
0.000_001
0.000_000_1

// --- Scientific notation patterns ---
1e1
1e2
1e3
1e-1
1e-2
1e-3
1.0e10
1.0e-10

// --- Multiple separators in different parts ---
1_2_3.4_5_6e7_8_9   // This would only be valid if exponent allows separators (check your grammar)
1_000.000_000e-1_0  // Same note as above

// --- Valid simple cases ---
0x0
0x1
0xA
0xa
0xF
0x00ABCDEF
0xdeadBEEF
0x0123456789ABCDEF
0x_1
0x_1234

// --- Lowercase and mixed-case checks ---
0xabc
0xABC
0xAbCdEf

// --- Valid with long sequences ---
0x1234_5678_9ABC_DEF0
0xABCDE_F1234
0xF00D_F00D
