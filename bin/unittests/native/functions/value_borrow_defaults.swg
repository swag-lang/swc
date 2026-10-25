#global private

#assert(#safety(Swag.SafetyWhat.ValueBorrow) == (#cfg == "devmode"))
struct Value { first, second, third: u64 }
#[Swag.NoInline]
func observe(value: Value, original: const *Value)->bool => &value == original and value.first == 281
#test
{
    var value: Value = Value{first: 281}
    let observed     = observe(value, &value)
    Swag.assert(observed)
}

// An enabled inline body keeps its guards when release disables them only by default.
#[Swag.NoInline, Swag.Safety(.ValueBorrow, false)]
func readWithoutEntryGuard(value: Value, extra: u64)->u64 => value.first + extra
#[Swag.NoInline, Swag.Safety(.ValueBorrow, true)]
func mutateLater(target: *Value)->u64 { target.first = 0; return 1 }
#[Swag.Inline, Swag.Safety(.ValueBorrow, true)]
func enabledInline(target: *Value)->u64 => readWithoutEntryGuard(target[], mutateLater(target))
#[Swag.NoInline]
func defaultCaller(target: *Value)->u64 => enabledInline(target)
#test
{
    var value: Value = Value{first: 317}
    let panic        = Swag.catchPanic(func|&value|() { discard defaultCaller(&value) })
    Swag.assert(panic.raised and value.first == 317)
}
