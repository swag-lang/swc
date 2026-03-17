#global fileprivate // swc-option sema-only
#global skip
func printf(format: cstring, args: cvarargs) {}

#test
{
    printf("toto")
}
