#global fileprivate

// Each type qualifier ('const', '#null') can appear at most once.
enum A1: const const *s32 { Z }        // swc-expected-error {{parser_err_duplicate_type_qualifier}}
enum A2: #null #null *s32 { Z }        // swc-expected-error {{parser_err_duplicate_type_qualifier}}
enum A3: #null const const *s32 { Z }  // swc-expected-error {{parser_err_duplicate_type_qualifier}}
