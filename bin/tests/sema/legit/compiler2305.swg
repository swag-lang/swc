#global fileprivate // swc-option sema-only
#global skip
func combine(fullnames: string...)
{
    foreach one in fullnames
    {
        @print(one)
    }
}

#test
{
}
