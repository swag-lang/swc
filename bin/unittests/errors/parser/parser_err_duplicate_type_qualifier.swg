#global private

// Each type qualifier ('const', '?') can appear at most once.
enum A1: const const *s32 { Z }        // swc-expected-error {{parser_err_duplicate_type_qualifier}}
enum A2: *s32?? { Z }               // swc-expected-error {{parser_err_duplicate_type_qualifier}}
enum A3: const const *s32? { Z }    // swc-expected-error {{parser_err_duplicate_type_qualifier}}
