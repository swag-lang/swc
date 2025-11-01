// swc-option lex-only

// --- Missing digits / incomplete literals ---
0b          // swc-expected-error {{MissingBinDigit}}
0b_         // swc-expected-error {{MissingBinDigit}}
0b__        // swc-expected-error {{ConsecutiveNumberSeparators}}
0b___       // swc-expected-error {{ConsecutiveNumberSeparators}}
0b0_        // swc-expected-error {{TrailingNumberSeparator}}
0b1_        // swc-expected-error {{TrailingNumberSeparator}}

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

// --- Invalid separators ---
0b__1       // swc-expected-error {{ConsecutiveNumberSeparators}}
0b1__0      // swc-expected-error {{ConsecutiveNumberSeparators}}
0b1_        // swc-expected-error {{TrailingNumberSeparator}}
0b0_        // swc-expected-error {{TrailingNumberSeparator}}
0b10__01    // swc-expected-error {{ConsecutiveNumberSeparators}}
0b101_      // swc-expected-error {{TrailingNumberSeparator}}

// --- Boundary and format checks ---
0b00000000
0b11111111
0b0000000000000000
0b1111111111111111
0b_         // swc-expected-error {{MissingBinDigit}}
0b0_______  // swc-expected-error {{ConsecutiveNumberSeparators}}
0b1_______  // swc-expected-error {{ConsecutiveNumberSeparators}}

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

// --- Invalid with misplaced underscores ---
0b10_10_        // swc-expected-error {{TrailingNumberSeparator}}
0b101__010      // swc-expected-error {{ConsecutiveNumberSeparators}}
0b1010__        // swc-expected-error {{ConsecutiveNumberSeparators}}
0b__1010        // swc-expected-error {{ConsecutiveNumberSeparators}}
0b1_0_1_0_      // swc-expected-error {{TrailingNumberSeparator}}

// --- Edge cases ---
0b0_0_0_0
0b1_1_1_1
0b__           // swc-expected-error {{ConsecutiveNumberSeparators}}
0b___          // swc-expected-error {{ConsecutiveNumberSeparators}}

// --- Invalid suffix ---
0b01G			// swc-expected-error {{InvalidBinDigit}}
