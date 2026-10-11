#[Swag.NoInline]
func repeatedCallObserved(value: s32)->s32 => value

#[Swag.NoInline]
func repeatedCallNullable(values: [*] s32)->[*] s32? => values

func repeatedCallChecked(values: [*] s32)->s32
{
    let optional = repeatedCallNullable(values)
    return repeatedCallObserved(optional![0])
}

func repeatedCallGuarded(values: [*] s32?)->s32
{
    if not values do
        return -1
    return repeatedCallObserved(values[0])
}

func repeatedCallOptional(values: [*] s32, enabled: s32)->[*] s32?
{
    if not repeatedCallObserved(enabled) do
        return null
    return values
}

func repeatedCallCold(values: [*] s32)->s32
{
    let optional = repeatedCallNullable(values)
    return repeatedCallObserved(optional![0])
}
