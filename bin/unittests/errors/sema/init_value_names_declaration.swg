#global private

// An initial value that does not convert to a declared type names the declaration. The wording is
// checked once; the other cases name the id.

func initValueLocal()->s32
{
    let count: s32 = "three"     // swc-expected-error {{'count' needs 's32', but its initial value has type 'string'}}
    return count
}

struct InitValueField
{
    ratio: bool = "yes"     // swc-expected-error {{sema_err_cannot_cast}}
}

func initValueParameter(flag: bool = "no")->bool => flag     // swc-expected-error {{sema_err_cannot_cast}}
