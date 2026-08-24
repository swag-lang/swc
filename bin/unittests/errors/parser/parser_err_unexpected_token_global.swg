// '#global' accepts an access level, 'export', a namespace, a condition, a 'using', or an
// attribute list. Anything else is unexpected, including a bare word.
#global generated     // swc-expected-error {{parser_err_unexpected_token}}
