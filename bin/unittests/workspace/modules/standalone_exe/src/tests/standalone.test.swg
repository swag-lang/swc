#global if #command == Swag.CompilerCommand.Test
using Core, RuntimeCtxDll

// The dependency is a shared library, and this executable named no link kind, so its code was
// linked in. Calling across what used to be a module boundary is what proves the archive carried
// real code and not an import stub.
#test
{
    gPatchedContext       = Swag.getContext()[]
    gPatchedContext.user0 = 42
    gPatchedContext.user2 = cast(u64) Swag.getContext()
    Swag.setContext(gPatchedContext)

    Swag.assert(ctxSharedReadContext() == 42)
    Swag.assert(ctxSharedContextMarker() == Swag.getContext().user2)
}

// The deliverable itself: an executable that links its dependencies in ships alone. A shared
// library beside it would be dead weight at best, and a second copy of a module already linked in
// at worst — two allocators and two runtime contexts in one process.
#test
{
    let artifactDir = Path.directoryName(Env.executablePath())
    Swag.assert(artifactDir != null)

    let libraries = expect Directory.enumerateFiles(artifactDir!, ".dll")
    Swag.assert(libraries.count == 0)
}
