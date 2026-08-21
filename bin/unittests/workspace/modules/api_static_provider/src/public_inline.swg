#global public

#[Swag.Macro]
func depMacroTwicePlus(value: s32, extra: s32 = 1)->s32
{
    let result = value * 2
    return result + extra
}

#[Swag.Mixin]
func depMixinAccumulateTwice(value: s32)
{
    let scaled = value * 2
    total += scaled
}

func(T) depMirror(value: T)->T => value

#[Swag.Inline, Swag.ConstExpr]
{
    func depInlineConstexpr(value: s32)->s32 => value * 2 + 2
    func depInlineIncrement(value: s32)->s32 => value + 1
}
