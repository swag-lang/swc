#global private

#[Swag.Optimize(true), Swag.NoInline]
func paired(values: *[8] f64)
{
    let left  = values[][0]
    let right = values[][1]
    let scale = values[][2]
    let first = left * Swag.sqrt(left)
    let last  = right * Swag.sqrt(right)
    values[][4] = scale / first
    values[][5] = scale / last
}

#[Swag.Optimize(false), Swag.NoInline]
func scalar(value, scale: f64)->f64
{
    return scale / (value * Swag.sqrt(value))
}

#test
{
    for first in 1 to 19
    {
        for last in 1 to 19
        {
            let left  = cast(f64, first * first) + 0.125
            let right = cast(f64, last * last) + 0.625
            var values: [8] f64 = [left, right, 0.03125, 0, 0, 0, 0, 0]
            paired(&values)
            Swag.assert(values[4] == scalar(left, values[2]))
            Swag.assert(values[5] == scalar(right, values[2]))
        }
    }
    for scale in [1e-80'f64, 1.0, 1e80]
    {
        var values: [8] f64 = [3.25 * scale, 7.125 * scale, 0.125, 0, 0, 0, 0, 0]
        paired(&values)
        Swag.assert(values[4] == scalar(values[0], values[2]))
        Swag.assert(values[5] == scalar(values[1], values[2]))
    }
}
