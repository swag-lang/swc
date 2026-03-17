#global fileprivate // swc-option sema-only
#global skip
//#global skip

//#[Swag.PrintBc]
#test
{
    {
        const vv: any = 6
        #assert(dref cast(const *s32) @dataof(vv) == 6)
    }
}
