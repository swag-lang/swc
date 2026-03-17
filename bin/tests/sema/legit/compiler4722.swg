#global fileprivate // swc-option sema-only
#global skip
internal
{
    private func toto() {}
}

#test
{
    toto()
}
