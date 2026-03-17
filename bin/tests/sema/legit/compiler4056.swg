#global fileprivate // swc-option sema-only
#global skip
func titi(x, y, z: &s32)
{
    x = y + z
}

#test
{
    var toto  = 0
    var toto1 = 1
    var toto2 = 2
    titi(&toto, &toto1, &toto2)
    @assert(toto == 3)
}
