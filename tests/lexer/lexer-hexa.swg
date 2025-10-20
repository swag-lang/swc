// --- Missing digits / incomplete literals ---
0x          // expected-error MissingHexDigit
0x_         // expected-error NumberSepStart
0x__        // expected-error NumberSepStart
0x___       // expected-error NumberSepStart
0x0_        // expected-error NumberSepEnd

// --- Valid simple cases ---
0x0
0x1
0xA
0xa
0xF
0x00ABCDEF
0xdeadBEEF
0x0123456789ABCDEF

// --- Valid with single underscore separators ---
0x1_2
0xDE_AD_BE_EF
0xAB_CD_EF
0x0_0
0xABC_DEF_123
// --- Invalid separators ---
0x__1       // expected-error NumberSepStart
0x1__2      // expected-error NumberSepMulti
0x_1        // expected-error NumberSepStart
0x1_        // expected-error NumberSepEnd
0xA__B      // expected-error NumberSepMulti
0xAB_       // expected-error NumberSepEnd

// --- Lowercase and mixed-case checks ---
0xabc
0xABC
0xAbCdEf

// --- Boundary and format checks ---
0x00000000
0xFFFFFFFF
0xffffFFFF
0x_         // expected-error NumberSepStart
0x0_______  // expected-error NumberSepMulti

// --- Valid with long sequences ---
0x1234_5678_9ABC_DEF0
0xABCDE_F1234
0xF00D_F00D

// --- Invalid with misplaced underscores ---
0x_1234         // expected-error NumberSepStart
0x12_34_        // expected-error NumberSepEnd
0x123__456      // expected-error NumberSepMulti
0x1234__        // expected-error NumberSepMulti
0x__1234        // expected-error NumberSepStart
