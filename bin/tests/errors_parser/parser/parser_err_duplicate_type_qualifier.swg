#global fileprivate

enum A: const const *s32 { Z } // swc-expected-error {{parser_err_duplicate_type_qualifier}}
