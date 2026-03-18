#global fileprivate
//#global skip

using Swag

func toto1(loc = #callerlocation)
{
    @assert(loc.funcName == "toto")
}

func toto()
{
    //@assert(#stringof(#me) == "__compiler1017.toto")
    toto1()
    #run toto1()
    #run
    {
        toto1()
    }
}

//#[Swag.PrintBc]
#test
{
    toto()
}

