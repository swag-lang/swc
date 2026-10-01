#global export

alias DepResultWord = u32

// Source exports replay these signatures when their imported bodies are requested.
#[Swag.Inline]
func depInlineNamedResult(value: DepResultWord)->{succeeded: bool, errorCode: DepResultWord}
{
    let succeeded = value == 0
    return {succeeded, value}
}

#[Swag.NoInline]
func depNamedResult(value: DepResultWord)->{succeeded: bool, errorCode: DepResultWord}
{
    let succeeded = value == 0
    return {succeeded, value}
}

#[Swag.NoInline]
func depAnonymousUnionResult(value: DepResultWord)->union { bits: DepResultWord; signedBits: s32 }
{
    var result: retval
    result.bits = value
    return result
}
