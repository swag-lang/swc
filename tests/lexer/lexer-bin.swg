// --- Missing digits / incomplete literals ---
0b          // expected-error MissingBinDigit
0b_         // expected-error NumberSepStart
0b__        // expected-error NumberSepStart
0b___       // expected-error NumberSepStart
0b0_        // expected-error NumberSepEnd
0b1_        // expected-error NumberSepEnd

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

// --- Invalid separators ---
0b__1       // expected-error NumberSepStart
0b1__0      // expected-error NumberSepMulti
0b_1        // expected-error NumberSepStart
0b_0        // expected-error NumberSepStart
0b1_        // expected-error NumberSepEnd
0b0_        // expected-error NumberSepEnd
0b10__01    // expected-error NumberSepMulti
0b101_      // expected-error NumberSepEnd

// --- Boundary and format checks ---
0b00000000
0b11111111
0b0000000000000000
0b1111111111111111
0b_         // expected-error NumberSepStart
0b0_______  // expected-error NumberSepMulti
0b1_______  // expected-error NumberSepMulti

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
0b_1010         // expected-error NumberSepStart
0b10_10_        // expected-error NumberSepEnd
0b101__010      // expected-error NumberSepMulti
0b1010__        // expected-error NumberSepMulti
0b__1010        // expected-error NumberSepStart
0b1_0_1_0_      // expected-error NumberSepEnd
0b_1_0_1_0      // expected-error NumberSepStart

// --- Edge cases ---
0b0_0_0_0
0b1_1_1_1
0b__           // expected-error NumberSepStart
0b___          // expected-error NumberSepStart