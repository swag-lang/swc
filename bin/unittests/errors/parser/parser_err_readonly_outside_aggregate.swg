#global private

// 'readonly' restricts writes to one field, so it only applies inside an aggregate body.
readonly const Value = 1     // swc-expected-error {{parser_err_readonly_outside_aggregate}}
