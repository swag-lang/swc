#global fileprivate

func notMacroParam(expr: #code s32) // swc-expected-error {{sema_err_code_type_restricted}}
{
}

func badReturn()->#code s32 => 1 // swc-expected-error {{sema_err_code_type_restricted}}

var badGlobal: #code s32 // swc-expected-error {{sema_err_code_type_restricted}}

func badLocal()
{
    let local = #code 1 // swc-expected-error {{sema_err_code_type_restricted}}
}
