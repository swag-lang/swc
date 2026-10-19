#[Swag.NoInline]
func deep(values: *[8] f64)
{
    var x = values[][0]
    var y = values[][1]

    x = Swag.sqrt(x) + 1.0'f64
    y = Swag.sqrt(y) + 1.0'f64

    x = Swag.sqrt(x) + 1.0'f64
    y = Swag.sqrt(y) + 1.0'f64

    x = Swag.sqrt(x) + 1.0'f64
    y = Swag.sqrt(y) + 1.0'f64

    x = Swag.sqrt(x) + 1.0'f64
    y = Swag.sqrt(y) + 1.0'f64

    x = Swag.sqrt(x) + 1.0'f64
    y = Swag.sqrt(y) + 1.0'f64

    x = Swag.sqrt(x) + 1.0'f64
    y = Swag.sqrt(y) + 1.0'f64

    x = Swag.sqrt(x) + 1.0'f64
    y = Swag.sqrt(y) + 1.0'f64

    x = Swag.sqrt(x) + 1.0'f64
    y = Swag.sqrt(y) + 1.0'f64

    x = Swag.sqrt(x) + 1.0'f64
    y = Swag.sqrt(y) + 1.0'f64

    x = Swag.sqrt(x) + 1.0'f64
    y = Swag.sqrt(y) + 1.0'f64

    x = Swag.sqrt(x) + 1.0'f64
    y = Swag.sqrt(y) + 1.0'f64

    x = Swag.sqrt(x) + 1.0'f64
    y = Swag.sqrt(y) + 1.0'f64

    x = Swag.sqrt(x) + 1.0'f64
    y = Swag.sqrt(y) + 1.0'f64

    x = Swag.sqrt(x) + 1.0'f64
    y = Swag.sqrt(y) + 1.0'f64

    x = Swag.sqrt(x) + 1.0'f64
    y = Swag.sqrt(y) + 1.0'f64

    x = Swag.sqrt(x) + 1.0'f64
    y = Swag.sqrt(y) + 1.0'f64

    x = Swag.sqrt(x) + 1.0'f64
    y = Swag.sqrt(y) + 1.0'f64

    x = Swag.sqrt(x) + 1.0'f64
    y = Swag.sqrt(y) + 1.0'f64

    x = Swag.sqrt(x) + 1.0'f64
    y = Swag.sqrt(y) + 1.0'f64

    x = Swag.sqrt(x) + 1.0'f64
    y = Swag.sqrt(y) + 1.0'f64

    x = Swag.sqrt(x) + 1.0'f64
    y = Swag.sqrt(y) + 1.0'f64

    x = Swag.sqrt(x) + 1.0'f64
    y = Swag.sqrt(y) + 1.0'f64

    x = Swag.sqrt(x) + 1.0'f64
    y = Swag.sqrt(y) + 1.0'f64

    x = Swag.sqrt(x) + 1.0'f64
    y = Swag.sqrt(y) + 1.0'f64

    x = Swag.sqrt(x) + 1.0'f64
    y = Swag.sqrt(y) + 1.0'f64

    x = Swag.sqrt(x) + 1.0'f64
    y = Swag.sqrt(y) + 1.0'f64

    x = Swag.sqrt(x) + 1.0'f64
    y = Swag.sqrt(y) + 1.0'f64

    x = Swag.sqrt(x) + 1.0'f64
    y = Swag.sqrt(y) + 1.0'f64

    x = Swag.sqrt(x) + 1.0'f64
    y = Swag.sqrt(y) + 1.0'f64

    x = Swag.sqrt(x) + 1.0'f64
    y = Swag.sqrt(y) + 1.0'f64

    x = Swag.sqrt(x) + 1.0'f64
    y = Swag.sqrt(y) + 1.0'f64

    x = Swag.sqrt(x) + 1.0'f64
    y = Swag.sqrt(y) + 1.0'f64

    values[][4] = x
    values[][5] = y
}

#main
{
    var values: [8] f64 = [81, 16, 0, 0, 0, 0, 0, 0]
    deep(&values)
    Swag.print("CHECK=", values[4] + values[5], "\n")
}
