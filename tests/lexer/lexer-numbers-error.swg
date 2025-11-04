// ============================================================================
// Lexer Numbers Error
// ============================================================================

// swc-option lex-only

// --- Missing digits / incomplete literals ---
0b          // swc-expected-error {{MissingBinDigit}}
0b_         // swc-expected-error {{MissingBinDigit}}
0b__        // swc-expected-error {{ConsecutiveNumberSeparators}}
0b___       // swc-expected-error {{ConsecutiveNumberSeparators}}
0b0_        // swc-expected-error {{TrailingNumberSeparator}}
0b1_        // swc-expected-error {{TrailingNumberSeparator}}

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

// --- Invalid separators in integers ---
123_        // swc-expected-error {{TrailingNumberSeparator}}
12__34      // swc-expected-error {{ConsecutiveNumberSeparators}}
1__2        // swc-expected-error {{ConsecutiveNumberSeparators}}
123___      // swc-expected-error {{ConsecutiveNumberSeparators}}

// --- Invalid separators in floats ---
123_.456    // swc-expected-error {{TrailingNumberSeparator}}
123._456    // swc-expected-error {{LeadingNumberSeparator}}
123.456_    // swc-expected-error {{TrailingNumberSeparator}}
1__2.34     // swc-expected-error {{ConsecutiveNumberSeparators}}
12.3__4     // swc-expected-error {{ConsecutiveNumberSeparators}}

// --- Invalid exponents ---
1e          // swc-expected-error {{MissingExponentDigits}}
1E          // swc-expected-error {{MissingExponentDigits}}
1e+         // swc-expected-error {{MissingExponentDigits}}
1e-         // swc-expected-error {{MissingExponentDigits}}
1.5e        // swc-expected-error {{MissingExponentDigits}}
1.5E+       // swc-expected-error {{MissingExponentDigits}}

// --- Invalid separator patterns ---
1_000_      // swc-expected-error {{TrailingNumberSeparator}}
1__000      // swc-expected-error {{ConsecutiveNumberSeparators}}
1_00__0     // swc-expected-error {{ConsecutiveNumberSeparators}}
1_.5        // swc-expected-error {{TrailingNumberSeparator}}
1._5        // swc-expected-error {{LeadingNumberSeparator}}
1.5_e2		// swc-expected-error {{TrailingNumberSeparator}}
1.5e_2		// swc-expected-error {{LeadingNumberSeparator}}
1.5e+_2		// swc-expected-error {{LeadingNumberSeparator}}
1.5e_+2		// swc-expected-error {{LeadingNumberSeparator}}

// --- Boundary cases ---
0_ // swc-expected-error {{TrailingNumberSeparator}}
1_ // swc-expected-error {{TrailingNumberSeparator}}
9_ // swc-expected-error {{TrailingNumberSeparator}}

123abc		// swc-expected-error {{InvalidNumberSuffix}}
42e10var	// swc-expected-error {{InvalidNumberSuffix}}

// --- Missing digits / incomplete literals ---
0x          // swc-expected-error {{MissingHexDigit}}
0x_         // swc-expected-error {{MissingHexDigit}}
0x__        // swc-expected-error {{ConsecutiveNumberSeparators}}
0x___       // swc-expected-error {{ConsecutiveNumberSeparators}}
0x0_        // swc-expected-error {{TrailingNumberSeparator}}

// --- Valid with single underscore separators ---
0x1_2
0xDE_AD_BE_EF
0xAB_CD_EF
0x0_0
0xABC_DEF_123
// --- Invalid separators ---
0x__1       // swc-expected-error {{ConsecutiveNumberSeparators}}
0x1__2      // swc-expected-error {{ConsecutiveNumberSeparators}}
0x1_        // swc-expected-error {{TrailingNumberSeparator}}
0xA__B      // swc-expected-error {{ConsecutiveNumberSeparators}}
0xAB_       // swc-expected-error {{TrailingNumberSeparator}}

// --- Boundary and format checks ---
0x00000000
0xFFFFFFFF
0xffffFFFF
0x_         // swc-expected-error {{MissingHexDigit}}
0x0_______  // swc-expected-error {{ConsecutiveNumberSeparators}}

// --- Invalid suffix ---
0xAFG			// swc-expected-error {{InvalidHexDigit}}

// --- Invalid with misplaced underscores ---
0x12_34_        // swc-expected-error {{TrailingNumberSeparator}}
0x123__456      // swc-expected-error {{ConsecutiveNumberSeparators}}
0x1234__        // swc-expected-error {{ConsecutiveNumberSeparators}}
0x__1234        // swc-expected-error {{ConsecutiveNumberSeparators}}
