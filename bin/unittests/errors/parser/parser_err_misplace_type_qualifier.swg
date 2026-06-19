#global fileprivate

// Canonical qualifier order is '#null const T'; any other order is misplaced.
enum A: const #null *s32 { Z }           // swc-expected-error {{parser_err_misplace_type_qualifier}}

func bad(a: const #null *s32) {}         // swc-expected-error {{parser_err_misplace_type_qualifier}}
