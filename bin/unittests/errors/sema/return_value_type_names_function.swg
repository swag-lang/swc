#global private

// A returned value that does not convert to the return type names the function and both types.
// The wording is checked once; the other case names the id.

func returnValueText()->s32 => "text"     // swc-expected-error {{return value has type 'string', but function 'returnValueText' returns 's32'}}

func returnValueStatement(flag: bool)->bool
{
    if flag do
        return true
    return 3.5     // swc-expected-error {{sema_err_cannot_cast}}
}
