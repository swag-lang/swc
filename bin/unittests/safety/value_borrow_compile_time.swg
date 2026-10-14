#global private

struct Value { first, second, third: u64 }
#[Swag.NoInline]
func read(value: Value, other: u64)->u64 => value.first + other
#[Swag.Inline]
func readInline(value: Value, other: u64)->u64 => value.first + other

#test
{
    const computed = #run
    {
        #[Swag.NoInline]
        func write(target: *Value)->u64
        {
            target.first = 0     // swc-expected-error {{safety_err_runtime}}
            return 1
        }
        var value: Value = {first: 11}
        discard read(value, write(&value))
        return 0
    }
}

#test
{
    const computed = #run
    {
        #[Swag.NoInline]
        func write(target: *Value)->u64
        {
            target.first = 0     // swc-expected-error {{safety_err_runtime}}
            return 1
        }
        var value: Value = {first: 13}
        discard readInline(value, write(&value))
        return 0
    }
}

var globalValue: Value
#[Swag.NoInline]
func writeGlobal()->u64
{
    globalValue.first = 0     // swc-expected-error {{safety_err_runtime}}
    return 1
}
#test
{
    const computed = #run read(globalValue, writeGlobal())
}

var inlineGlobal: Value
#[Swag.NoInline]
func writeInlineGlobal()->u64
{
    inlineGlobal.first = 0     // swc-expected-error {{safety_err_runtime}}
    return 1
}
#test
{
    const computed = #run readInline(inlineGlobal, writeInlineGlobal())
}
