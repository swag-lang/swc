#global public

namespace StrConv
{
    // Lets a type write its own text when [[Core.StrConv.convertAny]] formats it.
    interface IConvert
    {
        // Appends the text of the value to `buf`, honoring `convFmt` and the user format `strFormat`.
        mtd const convert(buf: *ConcatBuffer, convFmt: ConvertFormat, strFormat: string?)
    }
}
