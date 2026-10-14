#global private

struct Value { first, second: u64 }

#[Swag.NoInline]
func fillLocal(target: *u64) { target[] = 223 }

#[Swag.NoInline]
func makeAfterLocalWrite()->Value
{
    var local: u64
    fillLocal(&local)
    return {first: local}
}

#[Swag.NoInline]
func makeFallible(value: u64)->Value fail => {first: value}

#[Swag.NoInline]
func writeOther(value: Value, target: *u64)->u64
{
    target[] = 227
    return value.first
}

#test
{
    var other: u64
    let result = writeOther(makeAfterLocalWrite(), &other)
    Swag.assert(result == 223 and other == 227)
}

#test
{
    var other: u64
    let result = writeOther(expect makeFallible(229), &other)
    Swag.assert(result == 229 and other == 227)
}

#[Swag.NoInline]
func relayFallible(value: u64, target: *u64)->u64 fail
{
    return writeOther(try makeFallible(value), target)
}

#test
{
    var other: u64
    let result = expect relayFallible(239, &other)
    Swag.assert(result == 239 and other == 227)
}
