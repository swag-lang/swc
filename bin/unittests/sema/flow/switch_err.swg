#global private

func semaTest001()
{
    switch 1
    {
    case where true:
        break
    default:
        break
    }
}

func semaTest002()
{
    switch 1
    {
    case where false:
        break
    default:
        break
    }
}

func semaTest003()
{
    switch 1
    {
    case where false:
        break
    case where 1 < 2:
        break
    }
}

func semaTest004()
{
    switch #complete 1
    {
    case 1:
        break
    case where false:
        break
    }
}
