#global private

struct Large { first, second, third: u64 }

#[Swag.Inline]
func makeLarge()->Large
{
    var result: #returntype
    result = Large{11, 13, 17}
    return result
}

// The inline result is larger than the enclosing function's ABI return buffer.
#[Swag.NoInline]
func returnText()->string
{
    let value = makeLarge()
    Swag.assert(value.first == 11 and value.second == 13 and value.third == 17)
    return "kept"
}

#test { Swag.assert(returnText() == "kept") }

#[Swag.NoInline]
func returnScalar()->u64
{
    let value = makeLarge()
    return value.first + value.second + value.third
}

#test { Swag.assert(returnScalar() == 41) }

#[Swag.Inline]
func nestedLarge()->Large
{
    var result: #returntype
    let first = makeLarge()
    result = Large{first.third, first.second, first.first}
    return result
}

#[Swag.NoInline]
func enclosingLarge()->Large
{
    var result: #returntype
    result = Large{23, 29, 31}
    let inner = nestedLarge()
    Swag.assert(result.first == 23 and result.second == 29 and result.third == 31)
    Swag.assert(inner.first == 17 and inner.second == 13 and inner.third == 11)
    return result
}

#test
{
    let value = enclosingLarge()
    Swag.assert(value.first == 23 and value.second == 29 and value.third == 31)
}

// Two locals of the return type are two variables: only the returned one is the result.
#[Swag.Inline]
func twoNames()->Large
{
    var first:  #returntype
    var second: #returntype
    first.first   = 37
    second.second = 41
    return first
}

#test
{
    let value = twoNames()
    Swag.assert(value.first == 37 and value.second == 0)
}
