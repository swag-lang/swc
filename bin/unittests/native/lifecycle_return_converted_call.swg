#global private

// Returning a call result through an implicit conversion builds a new owned value from it. The
// return transfers that value to the caller; the conversion's storage is not destroyed on the way
// out as an operand temporary, or the caller would release it a second time.

var ConvertedDrops: s32
var ConvertedSeed:  s32    = 7
var ConvertedText:  string = "converted"

// Wider than a register, so it returns through caller storage.
struct Converted
{
    data:  [16] u8
    value: s32
}

impl Converted
{
    // Converts from a borrowed text, as 'String' does.
    #[Swag.Implicit]
    mtd opSet(source: string)
    {
        discard source
        .value = ConvertedSeed
    }

    mtd opDrop()
    {
        if .value != 0 do
            ConvertedDrops += 1
    }
}

func convertedSource()->string => ConvertedText

func convertedReturn()->Converted => convertedSource()

func convertedReturnFallible()->Converted fail
{
    if ConvertedSeed == 0 do
        return {}
    return convertedSource()
}

#test
{
    ConvertedDrops = 0
    scope
    {
        let plain = convertedReturn()
        Swag.assert(plain.value == 7)
        let fallible = expect convertedReturnFallible()
        Swag.assert(fallible.value == 7)
        Swag.assert(ConvertedDrops == 0)
    }

    Swag.assert(ConvertedDrops == 2)
}
