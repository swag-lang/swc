#global private

// Only 'break' and 'continue' can be replaced in '#inject'; other keywords are invalid.
func bad1()
{
    #inject(#code { break }, return = continue)          // swc-expected-error {{parser_err_inject_invalid_instruction}}
}

// 'name = ...' parses as a value binding, whose initializer must be an expression.
func bad2()
{
    #inject(#code { break }, foo = continue)             // swc-expected-error {{parser_err_unexpected_token}}
}
