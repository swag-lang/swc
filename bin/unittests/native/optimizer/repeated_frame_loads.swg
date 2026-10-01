#global private

#[Swag.NoInline]
func initialize(values: [..] f64)
{
    values[0] = 2
    values[1] = 3
    values[2] = 5
}

#[Swag.Optimize(true), Swag.NoInline]
func compute()->f64
{
    var values: [3] f64
    initialize(values)
    var result: f64 = 0
    for 2
    {
        let first  = values[0] - values[1]
        let second = values[0] - values[2]
        result += first * first + second * second
    }
    return result
}

#test
{
    Swag.assert(compute() == 20)
}
