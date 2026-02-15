#global internal
#global #[Swag.Complete]

enum FileLevelAttrEnum
{
    A,
    B,
}

#test
{
    var v = FileLevelAttrEnum.A
    switch v // swc-expected-error {{sema_err_switch_complete_enum_not_exhaustive}}
    {
        case FileLevelAttrEnum.A:
            break
        //case FileLevelAttrEnum.B:
        //    break
    }
}
