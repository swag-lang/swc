#global fileprivate
#global skip
#[Swag.Inline]
func titi()->s32 throw
{
    return 0
}

func toto()
{
    discard catch titi()
}
