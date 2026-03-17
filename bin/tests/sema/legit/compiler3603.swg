#global fileprivate // swc-option sema-only
#global skip
#[Swag.Incomplete]
enum Style: u8
{
    Default
    LineComment
}

#test
{
    var x: u8 = Style.Default
}
