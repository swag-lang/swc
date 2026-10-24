#global private

#[Swag.Macro]
func injected(stmt: #code) { #inject(stmt) }

#[Swag.Inline]
func readLocation(value: u64, padding: u64 = 0, loc = #callerlocation)->u64
{
    return value + padding + loc.lineStart
}

// A resolved injected argument belongs to the caller, even when its name matches
// the inline parameter. Its address home must not initialize itself.
#test
{
    let loc = #curlocation
    injected()
    {
        let observed = readLocation(1, loc: loc)
        Swag.assert(observed == 1 + loc.lineStart)
    }
}

struct Value { first, second, third: u64 }

#[Swag.Inline]
func readValue(value: Value, original: const *Value)->u64
{
    Swag.assert(&value == original)
    return value.first
}

#test
{
    var value: Value = {first: 41}
    injected()
    {
        injected()
        {
            let observed = readValue(value: value, original: &value)
            Swag.assert(observed == 41)
        }
    }
}

// Injection still honors a local shadow before the call is resolved.
#test
{
    var value: Value = {first: 43}
    injected()
    {
        var value: Value = {first: 47}
        let observed     = readValue(value: value, original: &value)
        Swag.assert(observed == 47)
    }
    Swag.assert(value.first == 43)
}
