#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Pixel

// Downscaling keeps the nearest source pixel and the image's bottom-up row order.
#test
{
    var source = Image.create(10, 7, .BGRA8)
    var destination = Image.create(6, 4, .BGRA8)
    let input = cast([*] u32, source.pixels.storage())
    for row in 7'u64
    {
        for column in 10'u64 do
            input[row * 10 + column] = cast(u32, row * 100 + column)
    }

    const Columns: [6] u32 = [0, 1, 3, 5, 6, 8]
    const Rows: [4] u32 = [0, 1, 3, 5]
    reduceBgraNearest(&source, &destination, Columns.buffer)
    let output = cast(const [*] u32, destination.pixels.storage())
    for row in 4'u64
    {
        for column in 6'u64 do
            Swag.require(output[row * 6 + column] == Rows[row] * 100 + Columns[column])
    }
}
