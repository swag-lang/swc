#global public
#global namespace Viewer

using Core

// Returns a decimal integer with its thousands set apart by a space, such as `1 280` or `-272 716 322`.
//
// Every viewer that sets a count or a reading in large type spells it this way, so a figure reads
// at a glance. Any other text — a hexadecimal, a float, a word — is returned unchanged.
func groupThousands(text: string)->String
{
    let digits = (text.count and text[0] == '-') ? text.count - 1 : text.count
    for index in text.count - digits until text.count where not Latin1.isDigit(text[index]) do
        return text

    var result: #returntype
    for byte, at in text
    {
        let left = text.count - at
        if at > text.count - digits and left % 3 == 0 do
            result += " "
        result += cast(rune, byte)
    }

    return result
}

// Returns `value` with its thousands set apart; see [[Viewer.groupThousands]].
func groupThousands(value: u64)->String => groupThousands(Format.toString("%", value))
