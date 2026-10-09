#global private

// An initial value that does not convert to a declared type names the declaration.

func initValueLocal()->s32
{
    let count: s32 = "three"     // swc-expected-error {{'count' needs 's32', but its initial value has type 'string'}}
    return count
}

struct InitValueField
{
    ratio: bool = "yes"     // swc-expected-error {{'ratio' needs 'bool', but its initial value has type 'string'}}
}

func initValueParameter(flag: bool = "no")->bool => flag     // swc-expected-error {{cannot cast from 'string' to 'bool'}}
