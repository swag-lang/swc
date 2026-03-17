#global fileprivate // swc-option sema-only
#global skip
func titi()
{
    struct AA
    {
        x:   s32
    }

    var v: AA
}

func tata()
{
    struct AA { x, y: s32 }

    var v: AA
}
