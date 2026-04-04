#global fileprivate

enum A: const #null *s32 { Z } // swc-expected-error {{parser_err_misplace_type_qualifier}}
