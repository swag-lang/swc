using RuntimeCtxDll

// `Swag.setContext` installs a POINTER to its argument, so the patched copy must outlive the frame
// that builds it: the dependency's own `#drop` runs after this one and reads `user0` through the
// installed pointer.
var gPatchedContext: Swag.Context

#init
{
    Swag.assert((Swag.getContext().user1 & CTX_SHARED_INIT_FLAG) != 0)
}

#premain
{
    Swag.assert((Swag.getContext().user1 & CTX_SHARED_PREMAIN_FLAG) != 0)
}

#drop
{
    gPatchedContext       = Swag.getContext()[]
    gPatchedContext.user0 = 43
    Swag.setContext(gPatchedContext)
}

#main {}
