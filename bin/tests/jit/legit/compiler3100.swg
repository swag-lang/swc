#global fileprivate // swc-option suite-jit
#global skip
//#global testerror

func msg() => "msg"

#test
{
    var x = 1
    #if false do
        #error(#run msg()
)
}
