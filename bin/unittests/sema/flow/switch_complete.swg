#global private

enum Color
{
    Red,
    Green,
    Blue
}

func semaTest001()
{
    var c = Color.Green
    switch #complete (c)
    {
    case Color.Red:
        break
    case Color.Green:
        break
    case Color.Blue:
        break
    }
}

func semaTest002()
{
    var c = Color.Red
    switch #complete (c)
    {
    case Color.Blue:
        break
    case Color.Red:
        break
    case Color.Green:
        break
    }
}
