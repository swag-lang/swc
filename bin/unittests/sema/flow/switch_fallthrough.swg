#global private

func semaTest001()
{
    var v = 1
    switch v
    {
        case 1:
            fallthrough
        case 2:
            break
        default:
            break
    }
}

func semaTest002()
{
    var v = 0
    switch v
    {
        case 0:
            fallthrough
        case 1:
            fallthrough
        case 2:
            break
    }
}

func semaTest003()
{
    var v = 1
    switch v
    {
        case 1:
            if v == 1
            {
                fallthrough
            }
        case 2:
            break
    }
}
