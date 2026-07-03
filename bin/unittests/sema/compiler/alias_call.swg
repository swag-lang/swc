#global private

#[Swag.Macro]
func macroPair(value: s32, stmt: #code void)
{
    let #alias0 = value
    let #alias1 = value * 2
    #inject(stmt)
}

#[Swag.Macro]
func macroPairForward(value: s32, stmt: #code void)
{
    macroPair(|#alias0, #alias1| value)
    {
        #inject(stmt)
    }
}

#[Swag.Mixin]
func declarePair(value: s32)
{
    const #alias0: s32 = value
    const #alias1: s32 = value + 1
}

func semaTest001()
{
    macroPair(|first| 21)
    {
        @assert(first == 21)
        @assert(#alias1 == 42)
    }
}

func semaTest002()
{
    macroPair(|left, right| 12)
    {
        @assert(left == 12)
        @assert(right == 24)
    }
}

func semaTest003()
{
    macroPairForward(|left, right| 14)
    {
        @assert(left == 14)
        @assert(right == 28)
    }
}

func semaTest004()
{
    declarePair(|named| 10)
    @assert(named == 10)
    @assert(#alias1 == 11)
}

func semaTest005()
{
    declarePair(|lhs, rhs| 20)
    @assert(lhs == 20)
    @assert(rhs == 21)
}

func semaTest006()
{
    declarePair(30)
    @assert(#alias0 == 30)
    @assert(#alias1 == 31)
}
