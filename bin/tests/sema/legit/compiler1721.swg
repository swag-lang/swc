#global fileprivate // swc-option sema-only
#global skip
#test
{
    alias a = s32
    {
        func A()
        {
            alias a = s32
        }
    }
}
