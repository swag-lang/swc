#global fileprivate // swc-option suite-jit
#global skip
func isThisRelease()->bool
{
    return true
}

#if #run isThisRelease() == false
{
    #warning("this should not be called !")
}
