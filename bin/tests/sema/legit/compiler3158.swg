#global fileprivate
#global skip
func printf(format: cstring, args: cvarargs) {}

#test
{
    printf("toto")
}
