#global fileprivate

// Only 'break' and 'continue' can be replaced in '#inject'; anything else is invalid.
func bad1()
{
    #inject(#code { break }, return = continue)          // swc-expected-error {{parser_err_inject_invalid_instruction}}
}

func bad2()
{
    #inject(#code { break }, foo = continue)             // swc-expected-error {{parser_err_inject_invalid_instruction}}
}
