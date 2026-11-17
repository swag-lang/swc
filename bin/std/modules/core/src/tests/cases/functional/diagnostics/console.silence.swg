#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#[Swag.Safety(.Assert, true)]
#test
{
    let underflow = Swag.catchPanic(func||() { Console.silent(false) })
    Swag.require(underflow.raised)
}
