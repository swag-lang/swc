// ============================================================================
// Lexer Numbers Error
// ============================================================================

// swc-option lex-only

// --- Missing digits / incomplete literals ---
0b          // swc-expected-error {{lex_err_missing_bin_digit}}
0b_         // swc-expected-error {{lex_err_missing_bin_digit}}
0b__        // swc-expected-error {{lex_err_consecutive_num_sep}}
0b___       // swc-expected-error {{lex_err_consecutive_num_sep}}
0b0_        // swc-expected-error {{lex_err_trailing_num_sep}}
0b1_        // swc-expected-error {{lex_err_trailing_num_sep}}

// --- Invalid separators ---
0b__1       // swc-expected-error {{lex_err_consecutive_num_sep}}
0b1__0      // swc-expected-error {{lex_err_consecutive_num_sep}}
0b1_        // swc-expected-error {{lex_err_trailing_num_sep}}
0b0_        // swc-expected-error {{lex_err_trailing_num_sep}}
0b10__01    // swc-expected-error {{lex_err_consecutive_num_sep}}
0b101_      // swc-expected-error {{lex_err_trailing_num_sep}}

// --- Boundary and format checks ---
0b00000000
0b11111111
0b0000000000000000
0b1111111111111111
0b_         // swc-expected-error {{lex_err_missing_bin_digit}}
0b0_______  // swc-expected-error {{lex_err_consecutive_num_sep}}
0b1_______  // swc-expected-error {{lex_err_consecutive_num_sep}}

// --- Invalid with misplaced underscores ---
0b10_10_        // swc-expected-error {{lex_err_trailing_num_sep}}
0b101__010      // swc-expected-error {{lex_err_consecutive_num_sep}}
0b1010__        // swc-expected-error {{lex_err_consecutive_num_sep}}
0b__1010        // swc-expected-error {{lex_err_consecutive_num_sep}}
0b1_0_1_0_      // swc-expected-error {{lex_err_trailing_num_sep}}

// --- Edge cases ---
0b0_0_0_0
0b1_1_1_1
0b__           // swc-expected-error {{lex_err_consecutive_num_sep}}
0b___          // swc-expected-error {{lex_err_consecutive_num_sep}}

// --- Invalid suffix ---
0b01G			// swc-expected-error {{lex_err_invalid_bin_digit}}

// --- Invalid separators in integers ---
123_        // swc-expected-error {{lex_err_trailing_num_sep}}
12__34      // swc-expected-error {{lex_err_consecutive_num_sep}}
1__2        // swc-expected-error {{lex_err_consecutive_num_sep}}
123___      // swc-expected-error {{lex_err_consecutive_num_sep}}

// --- Invalid separators in floats ---
123_.456    // swc-expected-error {{lex_err_trailing_num_sep}}
123._456    // swc-expected-error {{lex_err_leading_num_sep}}
123.456_    // swc-expected-error {{lex_err_trailing_num_sep}}
1__2.34     // swc-expected-error {{lex_err_consecutive_num_sep}}
12.3__4     // swc-expected-error {{lex_err_consecutive_num_sep}}

// --- Invalid exponents ---
1e          // swc-expected-error {{lex_err_missing_exponent}}
1E          // swc-expected-error {{lex_err_missing_exponent}}
1e+         // swc-expected-error {{lex_err_missing_exponent}}
1e-         // swc-expected-error {{lex_err_missing_exponent}}
1.5e        // swc-expected-error {{lex_err_missing_exponent}}
1.5E+       // swc-expected-error {{lex_err_missing_exponent}}

// --- Invalid separator patterns ---
1_000_      // swc-expected-error {{lex_err_trailing_num_sep}}
1__000      // swc-expected-error {{lex_err_consecutive_num_sep}}
1_00__0     // swc-expected-error {{lex_err_consecutive_num_sep}}
1_.5        // swc-expected-error {{lex_err_trailing_num_sep}}
1._5        // swc-expected-error {{lex_err_leading_num_sep}}
1.5_e2		// swc-expected-error {{lex_err_trailing_num_sep}}
1.5e_2		// swc-expected-error {{lex_err_leading_num_sep}}
1.5e+_2		// swc-expected-error {{lex_err_leading_num_sep}}
1.5e_+2		// swc-expected-error {{lex_err_leading_num_sep}}

// --- Boundary cases ---
0_ // swc-expected-error {{lex_err_trailing_num_sep}}
1_ // swc-expected-error {{lex_err_trailing_num_sep}}
9_ // swc-expected-error {{lex_err_trailing_num_sep}}

123abc		// swc-expected-error {{lex_err_invalid_number_suffix}}
42e10var	// swc-expected-error {{lex_err_invalid_number_suffix}}

// --- Missing digits / incomplete literals ---
0x          // swc-expected-error {{lex_err_missing_hex_digit}}
0x_         // swc-expected-error {{lex_err_missing_hex_digit}}
0x__        // swc-expected-error {{lex_err_consecutive_num_sep}}
0x___       // swc-expected-error {{lex_err_consecutive_num_sep}}
0x0_        // swc-expected-error {{lex_err_trailing_num_sep}}

// --- Valid with single underscore separators ---
0x1_2
0xDE_AD_BE_EF
0xAB_CD_EF
0x0_0
0xABC_DEF_123
// --- Invalid separators ---
0x__1       // swc-expected-error {{lex_err_consecutive_num_sep}}
0x1__2      // swc-expected-error {{lex_err_consecutive_num_sep}}
0x1_        // swc-expected-error {{lex_err_trailing_num_sep}}
0xA__B      // swc-expected-error {{lex_err_consecutive_num_sep}}
0xAB_       // swc-expected-error {{lex_err_trailing_num_sep}}

// --- Boundary and format checks ---
0x00000000
0xFFFFFFFF
0xffffFFFF
0x_         // swc-expected-error {{lex_err_missing_hex_digit}}
0x0_______  // swc-expected-error {{lex_err_consecutive_num_sep}}

// --- Invalid suffix ---
0xAFG			// swc-expected-error {{lex_err_invalid_hex_digit}}

// --- Invalid with misplaced underscores ---
0x12_34_        // swc-expected-error {{lex_err_trailing_num_sep}}
0x123__456      // swc-expected-error {{lex_err_consecutive_num_sep}}
0x1234__        // swc-expected-error {{lex_err_consecutive_num_sep}}
0x__1234        // swc-expected-error {{lex_err_consecutive_num_sep}}
