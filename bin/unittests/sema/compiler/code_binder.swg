#global private

#[Swag.Macro]
func macroPair(value: s32, stmt: #code(first: s32, second: s32))
{
    #inject(stmt, first = value, second = value * 2)
}

#[Swag.Macro]
func macroPairForward(value: s32, stmt: #code(first: s32, second: s32))
{
    macroPair(value, stmt)
}

func semaTest001()
{
    macroPair(21) #code(renamed)
    {
        Swag.assert(renamed == 21)
        Swag.assert(second == 42)
    }
}

func semaTest002()
{
    macroPair(12) #code(left, right)
    {
        Swag.assert(left == 12)
        Swag.assert(right == 24)
    }
}

func semaTest003()
{
    macroPairForward(14) #code(left, right)
    {
        Swag.assert(left == 14)
        Swag.assert(right == 28)
    }
}

func semaTest004()
{
    macroPair(30)
    {
        Swag.assert(first == 30)
        Swag.assert(second == 60)
    }
}
