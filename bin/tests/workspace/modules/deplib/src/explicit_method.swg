public impl DepCalculator
{
    mtd const add(value: f32)->f32
    {
        return cast(f32) .base + value
    }

    mtd const sub(value: s32)->s32
    {
        return .base - value
    }
}
