#global fileprivate // swc-option sema-only
#global skip
attr Toto(x: s32)

//#[Toto]
//func titi() {}

#test
{
    let x = #typeof(Toto)
    @assert(x == Toto)
}
