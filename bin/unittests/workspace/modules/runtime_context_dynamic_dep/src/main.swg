#global public

private var live = false

#init
{
    Swag.assert(not live)
    live = true
}

#premain
{
    Swag.assert(live)
}

#drop
{
    Swag.assert(live)
    live = false
}

func dependencyIsLive()->bool => live
