#global fileprivate

func bad()
{
    #inject(#code { break }, return = continue) // swc-expected-error {{parser_err_inject_invalid_instruction}}
}
