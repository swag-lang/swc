#global internal

#if #os == Swag.TargetOs.Windows
{
    const A = #os == Swag.TargetOs.Windows
    #assert(A)
    const B = true
}

#if #os == Swag.TargetOs.Linux
{
    const A = #os == Swag.TargetOs.Linux
    #assert(A)
    const B = true
}

#if #os == Swag.TargetOs.MaxOSX
{
    const A = #os == Swag.TargetOs.MaxOSX
    #assert(A)
    const B = true
}
