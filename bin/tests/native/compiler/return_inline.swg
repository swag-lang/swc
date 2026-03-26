#global fileprivate

#[Swag.Macro]
func macroValue(flag: bool)->s32
{
    if flag do
        return 11
    return 22
}

#[Swag.Mixin]
func mixinValue(flag: bool)->s32
{
    if flag do
        return 13
    return 24
}

#[Swag.Macro, Swag.CalleeReturn]
func macroCaller(stmt: #code void)
{
    #inject(stmt)
}

#[Swag.Mixin, Swag.CalleeReturn]
func mixinCaller(stmt: #code void)
{
    #inject(stmt)
}

func runMacroValue()->bool
{
    var reached = false
    let value = macroValue(true)
    reached = true
    return reached and value == 11
}

func runMixinValue()->bool
{
    var reached = false
    let value = mixinValue(true)
    reached = true
    return reached and value == 13
}

func runMacroCaller()->s32
{
    macroCaller()
    {
        return 7
    }

    return 9
}

func runMixinCaller()->bool
{
    mixinCaller()
    {
        return true
    }

    return false
}

#test
{
    @assert(runMacroValue())
    @assert(runMixinValue())
    @assert(runMacroCaller() == 7)
    @assert(runMixinCaller())
}
