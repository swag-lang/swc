#global private

func semaTest001()
{
    while true
    {
        var x = 0
        discard x
    }
}

func semaTest002()
{
    while true
    {
        while true
        {
            var x = 0
            discard x
        }
    }
}
