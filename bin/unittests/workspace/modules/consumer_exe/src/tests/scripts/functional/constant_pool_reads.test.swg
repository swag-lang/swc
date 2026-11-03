#global private
using Swag, RuntimeCtxDll

// The constants read inside the shared library must carry the same values the
// consumer sees, whatever the read compiled to there: the address fold turns
// a pool read into an instruction-pointer-relative access, and a library
// image is where that rewrite has gone wrong before.
#test
{
    Swag.assert(ctxPoolFirstName() == "black")
    Swag.assert(ctxPoolThirdName() == "red")
    Swag.assert(ctxPoolFirstValue() == 0x00000000)
    Swag.assert(ctxPoolFourthValue() == 0x0000FF00)

    for i in 4'u64
    {
        let name  = ctxPoolNameAt(i)
        let value = ctxPoolValueAt(i)
        Swag.assert(name.count >= 3)
        Swag.assert(value == 0 or value != 0)
    }

    Swag.assert(ctxPoolNameAt(1) == "white")
    Swag.assert(ctxPoolValueAt(2) == 0x00FF0000)
    Swag.assert(ctxPoolVectorSum(10) == 50)
}
