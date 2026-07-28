#global private

// A character literal is closed by its quote, and that quote is what separates it from
// its suffix. The earlier spelling wrote a second quote before the suffix.
const A = 'a''u8       // swc-expected-error {{parser_err_char_literal_suffix_quote}}
const B = ' ''u32      // swc-expected-error {{parser_err_char_literal_suffix_quote}}
const C = '0''rune     // swc-expected-error {{parser_err_char_literal_suffix_quote}}
