#global fileprivate

func bad()
{
    #inject(#code { break }, break = continue, break = continue) // swc-expected-error {{parser_err_inject_instruction_done}}
}
