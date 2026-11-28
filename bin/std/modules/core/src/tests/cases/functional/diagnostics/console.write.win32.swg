#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

using Swag

#test
{
    let maximum = cast(u64, Swag.U32.Max)
    Swag.require(Console.writeChunkLength(0) == 0)
    Swag.require(Console.writeChunkLength(maximum) == Swag.U32.Max)
    Swag.require(Console.writeChunkLength(maximum + 1) == Swag.U32.Max)
    Swag.require(Console.writeChunkLength(Swag.U64.Max) == Swag.U32.Max)
}
