#global fileprivate

// Stray closing delimiters at the top level are each reported as unexpected.
}                     // swc-expected-error {{parser_err_unexpected_token}}
)                     // swc-expected-error {{parser_err_unexpected_token}}
]                     // swc-expected-error {{parser_err_unexpected_token}}
