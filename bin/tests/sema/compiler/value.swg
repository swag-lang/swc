#global fileprivate

#if #os == Swag.TargetOs.Windows
{
    const A = #os == Swag.TargetOs.Windows
    #assert(A)
    const B = true
}

#test
{
    const A = #arch
    #assert(#typeof(A) == Swag.TargetArch)
}

#test
{
    const C = #cpu
    #assert(#typeof(C) == string)
    #assert(C != "")
}

#test
{
    const C = #cfg
    #assert(#typeof(C) == string)
    #assert(C != "")
}

#test
{
    const O = #swagos
    #assert(#typeof(O) == Swag.TargetOs)
}
