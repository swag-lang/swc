#global private

func guardedDefault(value: s32)
{
    switch value
    {
    default where value > 0: break // swc-expected-error {{parser_err_guarded_switch_default}}
    default: break
    }
}

func guardedDefaultWithoutSubject(flag: bool)
{
    switch
    {
    default where flag: break // swc-expected-error {{parser_err_guarded_switch_default}}
    }
}
