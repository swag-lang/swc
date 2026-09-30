#global private
using Swag

#[Swag.Optimize(true)]
func transform(values: *[8] f64)
{
    values[][4] = Swag.sqrt(values[][0]) / values[][2]
    values[][5] = Swag.sqrt(values[][1]) / values[][3]
}

#[Swag.Optimize(true)]
func reverse(values: *[8] f64)
{
    values[][4] = Swag.sqrt(values[][1])
    values[][5] = Swag.sqrt(values[][0])
}

#[Swag.Optimize(true)]
func overlapping(values: *[8] f64)
{
    values[][1] = Swag.sqrt(values[][0])
    values[][2] = Swag.sqrt(values[][1])
}

#[Swag.Optimize(true)]
func observe(values: *[8] f64)->f64
{
    values[][4] = Swag.sqrt(values[][0])
    values[][5] = Swag.sqrt(values[][1])
    return values[][5]
}

#[Swag.Optimize(true)]
func scaled(values: *[8] f64, scale: f64)
{
    values[][4] = values[][0] * scale
    values[][5] = values[][1] * scale
}

#test
{
    var values: [8] f64 = [81, 16, 3, 2, 0, 0, 0, 0]
    transform(&values)
    Swag.assert(values[4] == 3 and values[5] == 2)
    reverse(&values)
    Swag.assert(values[4] == 4 and values[5] == 9)
    let observed = observe(&values)
    Swag.assert(observed == 4)
    scaled(&values, 0.25)
    Swag.assert(values[4] == 20.25 and values[5] == 4)
    overlapping(&values)
    Swag.assert(values[1] == 9 and values[2] == 3)
}
