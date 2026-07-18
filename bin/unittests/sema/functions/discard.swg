#global private
#global #[Swag.ExplicitNullability]

func mustUse()->s32
{
    return 1
}

#[Swag.Discardable]
func canDiscard()->s32
{
    return 2
}

func semaTest001()
{
    let v = mustUse()
    @assert(v == 1)
}

func semaTest002()
{
    discard mustUse()
}

func semaTest003()
{
    canDiscard()
}
