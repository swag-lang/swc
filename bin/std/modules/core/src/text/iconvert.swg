#global public
#global #[Swag.ExplicitNullability]

namespace StrConv
{
    interface IConvert
    {
        mtd const convert(buf: #nonull *ConcatBuffer, convFmt: ConvertFormat, strFormat: #null string);
    }
}
