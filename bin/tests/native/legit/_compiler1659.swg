// 

#global fileprivate
//#[Swag.PrintBc]
#test
{
    let precision: u32 = 5
    let roundValue = 0.5 / (10 * precision)
    @assert(roundValue == 0.01)
}

