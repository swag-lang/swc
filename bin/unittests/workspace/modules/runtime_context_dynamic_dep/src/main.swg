#global public

private var live = false

#init
{
    Swag.assert(not live)
    live = true
    Swag.print("SWAG_DYNAMIC_DEP_INIT\n")
}

#premain
{
    Swag.assert(live)
    Swag.print("SWAG_DYNAMIC_DEP_PREMAIN\n")
}

#drop
{
    Swag.assert(live)
    Swag.print("SWAG_DYNAMIC_DEP_DROP\n")
    live = false
}

func dependencyIsLive()->bool => live
