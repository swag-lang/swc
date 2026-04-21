#global fileprivate

// A cast modifier cannot be repeated, regardless of which modifier is used.
#assert(cast #bit #bit (s32) 9)            // swc-expected-error {{parser_err_duplicated_modifier}}
#assert(cast #wrap #wrap (s32) 9)          // swc-expected-error {{parser_err_duplicated_modifier}}
#assert(cast #err #err (s32) 9)            // swc-expected-error {{parser_err_duplicated_modifier}}
