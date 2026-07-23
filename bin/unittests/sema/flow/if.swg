#global private

func semaTest001()
{
    if true {}

    if false {}
    else {}

    if false {}
    elif true {}
    else {}
}

func semaTest002()
{
    if true
    {
        var x = 0
    }
    else
    {
        var x = 1
    }
}

func semaTest003()
{
    if true
    {
        if true
        {
            var x = 0
        }
    }
}
