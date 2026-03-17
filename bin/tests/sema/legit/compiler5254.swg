#global fileprivate
#global skip
var G: s32
func(T) toto()->&T
{
    return &G
}

#test
{
    let str = #constref toto's32()
    toto's32() = 0
}
