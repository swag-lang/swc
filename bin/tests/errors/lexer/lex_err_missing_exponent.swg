#global fileprivate

// The exponent marker must be followed by digits, optionally preceded by a sign.
1e             // swc-expected-error {{lex_err_missing_exponent}}
1E             // swc-expected-error {{lex_err_missing_exponent}}
1.5e           // swc-expected-error {{lex_err_missing_exponent}}
1e+            // swc-expected-error {{lex_err_missing_exponent}}
1e-            // swc-expected-error {{lex_err_missing_exponent}}
