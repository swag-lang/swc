#global fileprivate

func semaTest001()
{
    var a: typeinfo = s32
    switch a
    {
        case s32: break
    }
}

func semaTest002()
{
    var a: typeinfo = f32
    switch a
    {
        case s32: break
        default: break
    }
}
