#global export

#if #os == Swag.TargetOs.Windows
{
    #foreignlib("ucrt")
    const ForeignLib = "ucrtbase"
    const ForeignLink = "ucrt"
}
#else
{
    #error("unsupported os")
}
