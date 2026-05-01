#global public

namespace StrConv
{
    interface IConvert
    {
        mtd const convert(buf: *ConcatBuffer, convFmt: ConvertFormat, strFormat: #null string);
    }
}
