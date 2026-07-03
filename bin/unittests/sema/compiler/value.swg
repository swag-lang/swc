#global private

#if #os == Swag.TargetOs.Windows
{
    const A = #os == Swag.TargetOs.Windows
    #assert(A)
    const B = true
}

func semaTest001()
{
    const A = #arch
    #assert(#typeof(A) == Swag.TargetArch)
}

func semaTest002()
{
    const C = #cpu
    #assert(#typeof(C) == string)
    #assert(C != "")
}

func semaTest003()
{
    const C = #cfg
    #assert(#typeof(C) == string)
    #assert(C != "")
}

func semaTest004()
{
    const O = #swagos
    #assert(#typeof(O) == Swag.TargetOs)
}
