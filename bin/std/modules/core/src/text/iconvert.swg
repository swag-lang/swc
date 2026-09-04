#global public

namespace StrConv
{
    // Defines the operations supported by i convert.
    interface IConvert
    {
        // Defines convert.
        mtd const convert(buf: *ConcatBuffer, convFmt: ConvertFormat, strFormat: string?)
    }
}
