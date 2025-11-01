// swc-option lex-only

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

// --- Invalid separators in integers ---
123_        // swc-expected-error {{TrailingNumberSeparator}}
12__34      // swc-expected-error {{ConsecutiveNumberSeparators}}
1__2        // swc-expected-error {{ConsecutiveNumberSeparators}}
123___      // swc-expected-error {{ConsecutiveNumberSeparators}}

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

// --- Invalid separators in floats ---
123_.456    // swc-expected-error {{TrailingNumberSeparator}}
123._456    // swc-expected-error {{LeadingNumberSeparator}}
123.456_    // swc-expected-error {{TrailingNumberSeparator}}
1__2.34     // swc-expected-error {{ConsecutiveNumberSeparators}}
12.3__4     // swc-expected-error {{ConsecutiveNumberSeparators}}

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

// --- Invalid exponents ---
1e          // swc-expected-error {{MissingExponentDigits}}
1E          // swc-expected-error {{MissingExponentDigits}}
1e+         // swc-expected-error {{MissingExponentDigits}}
1e-         // swc-expected-error {{MissingExponentDigits}}
1.5e        // swc-expected-error {{MissingExponentDigits}}
1.5E+       // swc-expected-error {{MissingExponentDigits}}

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

// --- Multiple separators in different parts ---
1_2_3.4_5_6e7_8_9   // This would only be valid if exponent allows separators (check your grammar)
1_000.000_000e-1_0  // Same note as above

// --- Boundary cases ---
0_ // swc-expected-error {{TrailingNumberSeparator}}
1_ // swc-expected-error {{TrailingNumberSeparator}}
9_ // swc-expected-error {{TrailingNumberSeparator}}

123abc		// swc-expected-error {{InvalidNumberSuffix}}
42e10var	// swc-expected-error {{InvalidNumberSuffix}}
