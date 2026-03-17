#global fileprivate // swc-option sema-only
#global skip
//#global testerror "Err0091"

//#include <stdio.h>

func main()->s32
{
    // printf() displays the string inside quotation
    @print("Hello, World!")
    return 0
}
