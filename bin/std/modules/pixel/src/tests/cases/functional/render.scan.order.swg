#global if #command == Swag.CompilerCommand.Test

using Core

// A dense line can reuse its predecessor's order, including after a local crossing.
#test
{
    var scratch: ScanScratch
    var line:    Array!{Crossing}
    for sample in 3
    {
        line.clear()
        for i in 192
        {
            var index = (i * 83) % 192
            if sample == 1
            {
                if index == 90
                {
                    index = 91
                }
                else if index == 91
                {
                    index = 90
                }
            }
            else if sample == 2
            {
                index = 191 - index
            }

            line.add({cast(f32, index), cast(s32, (i * 83) % 192)})
        }

        scratch.sortLine(&line)
        for sorted, i in line
        {
            Swag.require(sorted.x == cast(f32, i))
            var original = cast(s32, i)
            if sample == 1
            {
                if original == 90
                {
                    original = 91
                }
                else if original == 91
                {
                    original = 90
                }
            }
            else if sample == 2
            {
                original = 191 - original
            }

            Swag.require(sorted.winding == original)
        }
    }
}
