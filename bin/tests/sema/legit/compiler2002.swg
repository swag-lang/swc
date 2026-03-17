#global fileprivate // swc-option sema-only
#global skip
#test
{
    let c = '0''u8
    let b = ('a''u8 <= (c + 1) and (c + 1) <= 'z''u8)
}
