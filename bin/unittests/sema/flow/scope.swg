#global private

func semaTest001()
{
    #scope(Outer)
    {
        for 10
        {
            break to Outer
        }
    }
}

func semaTest002()
{
    #scope(Outer)
    for 10
    {
        break to Outer
    }
}

func semaTest003()
{
    #scope(A)
    {
        #scope(A)
        {
            break to A
        }

        break to A
    }
}

// A '#scope' is transparent to the bare statements: both reach the enclosing loop.
func semaTest004()
{
    for 10
    {
        #scope(Grouped)
        {
            if Swag.index == 3 do
                continue
            break
        }
    }
}

// The same holds when a switch is the nearest enclosing breakable construct.
func semaTest005()
{
    for 10
    {
        #scope(Grouped)
        {
            switch Swag.index
            {
            case 0:
                break
            default:
                continue
            }
        }
    }
}
