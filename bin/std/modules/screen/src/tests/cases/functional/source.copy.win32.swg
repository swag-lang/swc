#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

using Swag, Core

// A pitched partial readback lands on the intended bottom-up rows and leaves padding intact.
#test
{
    const Height           = 7_u64
    const SourcePitch      = 48_u64
    const DestinationPitch = 52_u64
    const SourceLeft       = 2_u64
    const DestinationLeft  = 4_u64
    const Top              = 2_u64
    const Bottom           = 5_u64
    const RowBytes         = 12_u64
    var source:      Array!{u8}
    var destination: Array!{u8}
    source.resize(Height * SourcePitch)
    destination.resize(Height * DestinationPitch)
    Memory.set(source.storage(), 0x12, source.count)
    Memory.set(destination.storage(), 0x5A, destination.count)
    for row in Top until Bottom
    {
        Memory.set(source.storage() + row * SourcePitch + SourceLeft * 4,
                   cast(u8, row + 1),
                   RowBytes)
    }

    let sourceTop         = source.storage() + Top * SourcePitch + SourceLeft * 4
    let destinationBottom = destination.storage() +
                            (Height - 1 - Top) * DestinationPitch + DestinationLeft * 4
    copyMappedBgraRows(destinationBottom, DestinationPitch, sourceTop, SourcePitch, RowBytes, Bottom - Top)

    for row in Height
    {
        for byte in DestinationPitch
        {
            let expected = row >= Top and
                           row < Bottom and
                           byte >= DestinationLeft * 4 and
                           byte < DestinationLeft * 4 + RowBytes ?
                           cast(u8, row + 1) : 0x5A_u8
            Swag.require(destination[(Height - 1 - row) * DestinationPitch + byte] == expected)
        }
    }
}
