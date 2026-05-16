#global public

func depDouble(value: s32)->s32
{
    return value * 2
}

func depScale(value: s32)->s32
{
    return value * 4
}

func depScale(value: f32)->f32
{
    return value * 4
}

struct DepCalculator
{
    base: s32
}

impl DepCalculator
{
    func make(base: s32)->DepCalculator
    {
        return {base}
    }

    mtd const add(value: s32)->s32
    {
        return .base + value
    }

    mtd const addTwice(value: s32)->s32 => .add(value) + value
}
