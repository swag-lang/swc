#global fileprivate

// Each '#inject' instruction can be replaced at most once.
func bad1()
{
    #inject(#code { break }, break = continue, break = continue)          // swc-expected-error {{parser_err_inject_instruction_done}}
}

func bad2()
{
    #inject(#code { continue }, continue = break, continue = break)       // swc-expected-error {{parser_err_inject_instruction_done}}
}
