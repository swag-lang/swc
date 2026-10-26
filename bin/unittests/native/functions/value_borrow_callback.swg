#global private

#[Swag.NoCopy]
struct Value
{
    first, second, third: u64
}

#[Swag.NoInline]
func invoke(value: Value, callback: func||(Value, const *Value)->bool)->bool
{
    return callback(value, &value)
}

#[Swag.NoInline]
func forward(value: Value, callback: func||(Value, const *Value)->bool)->bool
{
    return invoke(value, callback)
}

#[Swag.NoInline]
func same(value: Value, address: const *Value)->bool
{
    var sum = value.first
    sum += value.second
    return sum == 3 and &value == address
}

#test
{
    var value: Value = Value{first: 1, second: 2, third: 3}
    Swag.assert(invoke(value, &same))
    Swag.assert(forward(value, &same))
    let expected = 1'u64
    Swag.assert(invoke(value, func|expected|(arg, address) => arg.first == expected and &arg == address))
}

#[Swag.NoInline]
func addTwo(value: u64)->u64
{
    var result = value
    result += 2
    return result
}

func sameAfterLocalWrite(value: Value, address: const *Value)->bool
{
    return addTwo(value.first) == 3 and &value == address
}

#test
{
    var value: Value = Value{first: 1}
    Swag.assert(invoke(value, &sameAfterLocalWrite))
}

func sameWithMath(value: Value, address: const *Value)->bool
{
    return Swag.sqrt(cast(f64, value.first)) == 1 and &value == address
}

#test
{
    var value: Value = Value{first: 1}
    Swag.assert(invoke(value, &sameWithMath))
}

#[Swag.NoInline]
func invokeFunction(value: Value, callback: func(Value, const *Value)->bool)->bool
{
    return callback(value, &value)
}

#test
{
    var value: Value = Value{first: 1, second: 2}
    Swag.assert(invokeFunction(value, &same))
}

func sameWithStatic(value: Value, address: const *Value)->bool
{
    #static if #sizeof(Value) == 24
    {
        #static switch #sizeof(Value)
        {
        case 24: return &value == address
        default: return missingStaticSwitchFunction(value)
        }
    }
    else do
        return missingStaticIfFunction(value)
}

#test
{
    var value: Value
    Swag.assert(invoke(value, &sameWithStatic))
}

struct StoredCallback
{
    callback: func||(Value, const *Value)->bool
}

struct NestedCallback
{
    stored: StoredCallback
}

#test
{
    var value:  Value = Value{first: 1, second: 2}
    var holder: StoredCallback = StoredCallback{callback: &same}
    Swag.assert(invoke(value, holder.callback))
    var nested: NestedCallback = NestedCallback{stored: StoredCallback{callback: &same}}
    Swag.assert(invoke(value, nested.stored.callback))
}

#test
{
    var value:    Value = Value{first: 1, second: 2}
    var callback: func||(Value, const *Value)->bool = &same
    let selected        = callback
    Swag.assert(invoke(value, selected))
}

struct AddressHolder
{
    target:        const *Value?
    first, second: u64
}

impl AddressHolder
{
    #[Implicit]
    mtd opSet(address: const *Value) { .target = address }
}

func sameWithConstructedHeader(value: Value, address: const *Value)->bool
{
    var holder: AddressHolder = address
    return holder.target == &value
}

#test
{
    var value: Value
    Swag.assert(invoke(value, &sameWithConstructedHeader))
}

#[Swag.NoInline]
func makeAddressHolder(address: const *Value)->AddressHolder
{
    var result: #returntype = address
    return result
}

func sameWithReturnedHeader(value: Value, address: const *Value)->bool
{
    let holder = makeAddressHolder(address)
    return holder.target == &value
}

#test
{
    var value: Value
    Swag.assert(invoke(value, &sameWithReturnedHeader))
}
