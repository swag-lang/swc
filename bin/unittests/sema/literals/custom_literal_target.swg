#global private

struct Duration { milliseconds: s32 }

impl Duration
{
    #[Swag.ConstExpr, Swag.Implicit]
    mtd(suffix: string) opSetLiteral(value: s32)
    {
        #assert(suffix == "ms")
        .milliseconds = value
    }
}

const ExplicitCast    = cast(Duration, 30_ms)
const Typed: Duration = 30_ms
#assert(ExplicitCast.milliseconds == 30 and Typed.milliseconds == 30)
