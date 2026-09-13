#global private

var Calls: [4] u32

#[Swag.NoInline]
func nextValue(slot: u32)->s32
{
    Calls[slot] += 1
    return cast(s32) (slot + 1) * 10
}

#[Swag.Inline]
func mixedUses(repeated, assigned, addressed: s32, values: [..] s32)->s32
{
    var total          = repeated + repeated
    var assignedValue  = assigned
    var addressedValue = addressed
    assignedValue += 3
    let pointer = &addressedValue
    pointer[] += 5
    for value in values do
        total += value
    return total + assignedValue + pointer[]
}

#[Swag.Inline]
func readAddressed(value: s32)->s32
{
    let pointer = &value
    return pointer[]
}

#[Swag.Inline]
func(T) genericRepeat(value: T)->T => value + value

#[Swag.Inline]
func countOnly(values: s32...)->u64 => values.count

#[Swag.Inline]
func sumPack(values: s32...)->s32
{
    var total: s32
    for value in values do
        total += value
    return total + cast(s32) values.count
}

#[Swag.Inline]
func mutateElement(values: [..] s32, index: u32)->s32
{
    values[index] += 7
    let pointer = &values[index]
    pointer[] += 3
    return values[index]
}

#[Swag.NoInline]
func nextIndex()->u32
{
    Calls[0] += 1
    return 1
}

#test
{
    Calls = [0, 0, 0, 0]
    var values: [2] s32 = [4, 7]
    let result = mixedUses(nextValue(0), nextValue(1), nextValue(2), values)
    Swag.assert(result == 89)
    Swag.assert(Calls[0] == 1)
    Swag.assert(Calls[1] == 1)
    Swag.assert(Calls[2] == 1)

    // A later expansion has independent usage facts and caller expressions.
    var first  = 10
    var second = 20
    var third  = 30
    let again  = mixedUses(first, second, third, values)
    Swag.assert(again == 89)
    Swag.assert(first == 10)
    Swag.assert(second == 20)
    Swag.assert(third == 30)

    let genericResult = genericRepeat(nextValue(3))
    Swag.assert(genericResult == 80)
    Swag.assert(Calls[3] == 1)

    let addressedResult = readAddressed(nextValue(3))
    Swag.assert(addressedResult == 40)
    Swag.assert(Calls[3] == 2)
}

#test
{
    var first  = 11
    var second = 22
    Swag.assert(countOnly(first, second) == 2)
    Swag.assert(countOnly() == 0)
    Swag.assert(sumPack(first, second) == 35)
}

#test
{
    // Address and mutation facts also apply to identifiers nested in an operand.
    var values: [2] s32 = [11, 22]
    let result = mutateElement(values, 1)
    Swag.assert(result == 32)
    Swag.assert(values[0] == 11)
    Swag.assert(values[1] == 32)

    Calls[0] = 0
    let repeated = genericRepeat(values[nextIndex()])
    Swag.assert(repeated == 64)
    Swag.assert(Calls[0] == 1)
}
