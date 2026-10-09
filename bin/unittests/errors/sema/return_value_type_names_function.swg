#global private

// A returned value that does not convert to the return type names the function and both types.

func returnValueText()->s32 => "text"     // swc-expected-error {{return value has type 'string', but function 'returnValueText' returns 's32'}}

func returnValueStatement(flag: bool)->bool
{
    if flag do
        return true
    return 3.5     // swc-expected-error {{return value has type 'f64', but function 'returnValueStatement' returns 'bool'}}
}
