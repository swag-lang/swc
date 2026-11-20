#global private

"\x80"           // swc-expected-error {{lex_err_non_ascii_string_escape}}
"prefix\xFFend"  // swc-expected-error {{lex_err_non_ascii_string_escape}}
// swc-expected-error@+2 {{lex_err_non_ascii_string_escape}}
"""prefix
   \xa0
   """
