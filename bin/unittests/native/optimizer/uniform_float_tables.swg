#global private

const Positive:    [4] f64 = [0.25, 0.5, 1.0, 2.0]
const NonPositive: [4] f64 = [-0.25, 0.0, -1.0, -2.0]
const Mixed:       [4] f64 = [0.25, 0.5, 1.0, -2.0]
const Positive32:  [4] f32 = [0.25, 0.5, 1.0, 2.0]
const Mixed32:     [4] f32 = [-0.25, -0.5, -1.0, 2.0]
const Unordered:   [4] f64 = [cast #bit (f64, 0x7FF8000000000000'u64), -0.5, 0.0, -2.0]

#[Swag.NoInline, Swag.Optimize(true)]
func positive(index: u64)->u64
{
    if Positive[index] > 0 do return index + 7
    return index + 13
}

#[Swag.NoInline, Swag.Optimize(true)]
func nonPositive(index: u64)->u64
{
    if NonPositive[index] > 0 do return index + 7
    return index + 13
}

#[Swag.NoInline, Swag.Optimize(true)]
func mixed(index: u64)->u64
{
    if Mixed[index] > 0 do return index + 7
    return index + 13
}

#[Swag.NoInline, Swag.Optimize(true)]
func positive32(index: u64)->u64
{
    if Positive32[index] > 0'f32 do return index + 7
    return index + 13
}

#[Swag.NoInline, Swag.Optimize(true)]
func mixed32(index: u64)->u64
{
    if Mixed32[index] > 0'f32 do return index + 7
    return index + 13
}

#[Swag.NoInline, Swag.Optimize(true)]
func unordered(index: u64)->u64
{
    if Unordered[index] > 0 do return index + 7
    return index + 13
}

#test
{
    for index in 4'u64
    {
        Swag.assert(positive(index) == index + 7)
        Swag.assert(nonPositive(index) == index + 13)
        Swag.assert(mixed(index) == index + (index == 3 ? 13 : 7))
    }
}

#test
{
    for index in 4'u64
    {
        Swag.assert(positive32(index) == index + 7)
        Swag.assert(mixed32(index) == index + (index == 3 ? 7 : 13))
    }
}

#test
{
    for index in 4'u64 do
        Swag.assert(unordered(index) == index + 13)
}
