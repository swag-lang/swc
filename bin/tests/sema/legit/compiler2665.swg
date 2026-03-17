#global fileprivate
#global skip
func toto()->{ x: s32, y: s32 }
{
    return {10, 20}
}

#test
{
    let h = toto()
    var x = {h}
}
