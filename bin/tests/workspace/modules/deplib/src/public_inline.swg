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
