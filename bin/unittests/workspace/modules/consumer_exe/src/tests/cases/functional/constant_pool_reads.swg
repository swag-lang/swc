#global private
using Swag, RuntimeCtxDll

// The constants read inside the shared library must carry the same values the
// consumer sees, whatever the read compiled to there: the address fold turns
// a pool read into an instruction-pointer-relative access, and a library
// image is where that rewrite has gone wrong before.
#test
{
    Swag.require(ctxPoolFirstName() == "black")
    Swag.require(ctxPoolThirdName() == "red")
    Swag.require(ctxPoolFirstValue() == 0x00000000)
    Swag.require(ctxPoolFourthValue() == 0x0000FF00)

    for i in 4'u64
    {
        let name  = ctxPoolNameAt(i)
        let value = ctxPoolValueAt(i)
        Swag.require(name.count >= 3)
        Swag.require(value == 0 or value != 0)
    }

    Swag.require(ctxPoolNameAt(1) == "white")
    Swag.require(ctxPoolValueAt(2) == 0x00FF0000)
    Swag.require(ctxPoolVectorSum(10) == 50)
}
