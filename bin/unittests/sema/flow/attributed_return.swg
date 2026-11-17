#global private

func plainScopedReturn()->s32
{
    scope
    {
        return 11
    }
}

func warningScopedReturn()->s32
{
    #[Swag.Warning("sema_warn_unreachable_code", .Warning)]
    {
        return 12
    }
}

func safetyScopedReturn()->s32
{
    #[Swag.Safety(.BoundCheck, false)]
    {
        return 13
    }
}

func nestedAttributedReturn(flag: bool)->s32
{
    #[Swag.Warning("sema_warn_unreachable_code", .Warning)]
    {
        #[Swag.Safety(.BoundCheck, false)]
        {
            if flag do return 14
            else do return 15
        }
    }
}

func unreachableAfterAttributedReturn()->s32
{
    #[Swag.Safety(.BoundCheck, false)]
    {
        return 16
    }
    let never = 0 // swc-expected-warning {{sema_warn_unreachable_code}}
    return never
}

#test
{
    Swag.require(plainScopedReturn() == 11)
    Swag.require(warningScopedReturn() == 12)
    Swag.require(safetyScopedReturn() == 13)
    Swag.require(nestedAttributedReturn(true) == 14)
    Swag.require(nestedAttributedReturn(false) == 15)
    Swag.require(unreachableAfterAttributedReturn() == 16)
}
