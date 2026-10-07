#global private

#[Swag.Inline]
func choose(values: [16] u64, index: u32)->u64 => values[index] + values[15 - index]

#[Swag.NoInline]
func chooseLocal(source: *[16] u64, index: u32)->u64
{
    let values = source[]
    return choose(values, index)
}

#[Swag.NoInline]
func mutateFirst(values: *[16] u64)->u32
{
    values[][0] += 1000
    return 0
}

#[Swag.Inline]
func withAlias(values: [16] u64, target: *[16] u64)->u64
{
    target[][0] += 1000
    return values[0] + values[15]
}

#[Swag.Inline]
func withCallback(values: [16] u64, target: *[16] u64, callback: func(*[16] u64)->u32)->u64
{
    discard callback(target)
    return values[0] + values[15]
}

#[Swag.Inline]
func changed(values: [16] u64)->u64
{
    values[0] += 123
    return values[0] + values[15]
}

#test
{
    var values: [16] u64
    for i in 16 do
        values[i] = i * 17
    for index in 16'u32 do
        Swag.assert(chooseLocal(&values, index) == 255)
    Swag.assert(changed(values) == 378)
    Swag.assert(values[0] == 0)
}

#test
{
    var values: [16] u64
    values[0]  = 7
    values[15] = 11
    // The first argument is a value snapshot, taken before evaluating the second.
    Swag.assert(choose(values, mutateFirst(&values)) == 18)
    Swag.assert(values[0] == 1007)
    Swag.assert(withAlias(values, &values) == 1018)
    Swag.assert(values[0] == 2007)
    Swag.assert(withCallback(values, &values, &mutateFirst) == 2018)
    Swag.assert(values[0] == 3007)
}

struct Tracked
{
    value: u64
}

impl Tracked
{
    mtd opPostCopy() { .value += 1 }
}

#[Swag.Inline]
func chooseTracked(values: [4] Tracked)->u64 => values[0].value + values[3].value

#test
{
    var values: [4] Tracked
    values[0].value = 5
    values[3].value = 9
    Swag.assert(chooseTracked(values) == 16)
    Swag.assert(values[0].value == 5 and values[3].value == 9)
}
