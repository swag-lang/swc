#global fileprivate
#global skip
func titi(loc = #callerlocation)
{
    @assert(loc.funcName == "__compiler1128.tata")
}

func tata()
{
    titi()
}

#test
{
    tata()
}
