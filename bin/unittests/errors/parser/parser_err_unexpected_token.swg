#global private

// Stray closing delimiters at the top level are each reported as unexpected.
}                     // swc-expected-error {{parser_err_unexpected_token}}
)                     // swc-expected-error {{parser_err_unexpected_token}}
]                     // swc-expected-error {{parser_err_unexpected_token}}

// An enum body holds values, not declarations: 'using' is a statement and has no place
// in one. An enum owns the values it declares and nothing else.
enum Basic { FailedToLoad, FailedToSave }

enum Extended
{
    using Basic     // swc-expected-error {{parser_err_unexpected_token}}
    NotFound = 100
}
