#global private

struct BorrowedValue
{
    first:  u64
    second: u64
}

#[Swag.NoInline]
func readAlongsideWrite(value: BorrowedValue, destination: *BorrowedValue)->u64
{
    destination.first = 29
    return value.first
}

#test
{
    var value  = BorrowedValue{11, 13}
    var other  = BorrowedValue{17, 19}
    let result = readAlongsideWrite(value, &other)
    Swag.assert(result == 11 and other.first == 29)
}

#test
{
    var value  = BorrowedValue{31, 37}
    let result = readAlongsideWrite(#copy value, &value)
    Swag.assert(result == 31 and value.first == 29)
}

#test
{
    #[Swag.NoInline]
    func mutateBorrow(value: BorrowedValue, destination: *BorrowedValue)->u64
    {
        destination.first = 41     // swc-expected-error {{safety_err_runtime}}
        return value.first
    }

    func conflict()->u64
    {
        var value = BorrowedValue{43, 47}
        return mutateBorrow(value, &value)
    }

    const result = #run conflict()
}

#[Swag.Inline]
func inlineReadAlongsideWrite(value: BorrowedValue, destination: *BorrowedValue)->u64
{
    destination.first = 53
    return value.first
}

#test
{
    var value = BorrowedValue{59, 61}
    var other = BorrowedValue{67, 71}
    Swag.assert(inlineReadAlongsideWrite(value, &other) == 59)
    Swag.assert(inlineReadAlongsideWrite(#copy value, &value) == 59)
    Swag.assert(value.first == 53 and other.first == 53)
}

#test
{
    #[Swag.Inline]
    func inlineConflict(value: BorrowedValue, destination: *BorrowedValue)->u64
    {
        destination.first = 73     // swc-expected-error {{safety_err_runtime}}
        return value.first
    }

    func conflict()->u64
    {
        var value = BorrowedValue{79, 83}
        return inlineConflict(value, &value)
    }

    const result = #run conflict()
}

// The original Zig parent/field counterexample must fail during compile-time execution too.
#test
{
    struct Parent { item: BorrowedValue }
    #[Swag.NoInline]
    func mutate(parent: *Parent, item: BorrowedValue)->u64
    {
        parent.item.first = 0     // swc-expected-error {{safety_err_runtime}}
        return item.first
    }
    func conflict()->u64
    {
        var parent: Parent = {item: {first: 11}}
        return mutate(&parent, parent.item)
    }
    const result = #run conflict()
}

#test
{
    #[Swag.NoInline]
    func write(target: *BorrowedValue)->u64
    {
        target.first = 0     // swc-expected-error {{safety_err_runtime}}
        return 1
    }
    #[Swag.NoInline]
    func read(value: BorrowedValue, extra: u64)->u64 => value.first + extra
    func conflict()->u64
    {
        var value: BorrowedValue = {first: 13}
        return read(value, write(&value))
    }
    const result = #run conflict()
}

#test
{
    #[Swag.NoInline]
    func mutate(value: BorrowedValue, target: *BorrowedValue)->u64
    {
        Swag.init(target)     // swc-expected-error {{safety_err_runtime}}
        return value.first
    }
    func conflict()->u64
    {
        var value: BorrowedValue = {first: 17}
        return mutate(value, &value)
    }
    const result = #run conflict()
}

#test
{
    #[Swag.NoInline]
    func mutate(value: BorrowedValue, target: *BorrowedValue)->u64
    {
        Swag.memset(target, 0, #sizeof(BorrowedValue))     // swc-expected-error {{safety_err_runtime}}
        return value.first
    }
    func conflict()->u64
    {
        var value: BorrowedValue = {first: 19}
        return mutate(value, &value)
    }
    const result = #run conflict()
}

#test
{
    #[Swag.NoInline]
    func mutate(value: BorrowedValue, target: *BorrowedValue)->u64
    {
        discard Swag.atomicExchange(&target.first, 0)     // swc-expected-error {{safety_err_runtime}}
        return value.first
    }
    func conflict()->u64
    {
        var value: BorrowedValue = {first: 23}
        return mutate(value, &value)
    }
    const result = #run conflict()
}

#test
{
    #[Swag.NoInline]
    func mutate(value: BorrowedValue, bits: u64)->u64
    {
        cast(*u64, bits)[] = 0     // swc-expected-error {{safety_err_runtime}}
        return value.first
    }
    func conflict()->u64
    {
        var value: BorrowedValue = {first: 29}
        return mutate(value, cast(u64, &value))
    }
    const result = #run conflict()
}
