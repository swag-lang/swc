#global private

struct CopyCounter
{
    value:  u64
    target: *u64?
}

impl CopyCounter
{
    mtd opPostCopy() { .value += 1 }
}

#[Swag.NoInline]
func readWithCopy(value: CopyCounter)->u64
{
    let copy = value
    return value.value + copy.value
}

#[Swag.NoInline]
func invoke(value: CopyCounter, callback: func||()->u64)->u64
{
    return callback() + value.value
}

func copyLocal()->u64
{
    var source: CopyCounter = CopyCounter{value: 5}
    let copy = source
    return copy.value
}

#test
{
    var value: CopyCounter = CopyCounter{value: 3}
    Swag.assert(readWithCopy(value) == 7)
    Swag.assert(value.value == 3)
    Swag.assert(invoke(value, &copyLocal) == 9)
}

struct Destination
{
    value:  u64
    target: *CopyCounter
}

#[Swag.NoInline]
func updateDistinct(value: CopyCounter, destination: *Destination)->u64
{
    destination.value = 13
    return value.value
}

#test
{
    var value:       CopyCounter = CopyCounter{value: 11}
    var destination: Destination = Destination{target: &value}
    let observed = updateDistinct(value, &destination)
    Swag.assert(observed == 11)
    Swag.assert(destination.value == 13)
}
