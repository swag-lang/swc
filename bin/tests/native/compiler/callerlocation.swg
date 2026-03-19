// Migrated from the former native/legit suite (_compiler1017.swg).
#global fileprivate
using Swag

func legitCallerLocationTarget(loc = #callerlocation)
{
    @assert(loc.funcName == "legitCallerLocationEntry")
}

func legitCallerLocationEntry()
{
    legitCallerLocationTarget()
    #run legitCallerLocationTarget()
    #run
    {
        legitCallerLocationTarget()
    }
}

#test
{
    legitCallerLocationEntry()
}
