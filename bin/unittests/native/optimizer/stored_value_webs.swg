#global private
using Swag

#[Swag.Optimize(true)]
func update(values: *[8] f64, chooseFirst: bool)
{
    var value: f64
    if chooseFirst do value = values[][0]
    else do value = values[][1]
    value       *= value
    values[][4] = value
    value       = values[][2] * values[][3]
    values[][5] = value
    values[][6] = values[][4] + values[][5]
    for 3
    {
        value       = values[][6] + 0.5
        values[][6] = value
    }
    values[][7] = values[][4] + value
}

#test
{
    var first: [8] f64 = [2, 3, 4, 5, 0, 0, 0, 0]
    var second         = first
    update(&first, true)
    update(&second, false)
    Swag.assert(first[4] == 4 and first[5] == 20 and first[6] == 25.5 and first[7] == 29.5)
    Swag.assert(second[4] == 9 and second[5] == 20 and second[6] == 30.5 and second[7] == 39.5)
}
