#global if #command == Swag.CompilerCommand.Test
using Core, RuntimeCtxDll

// Imported code uses the executable runtime context.
#test
{
    gPatchedContext       = Swag.getContext()[]
    gPatchedContext.user0 = 42
    gPatchedContext.user2 = cast(u64, Swag.getContext())
    Swag.setContext(gPatchedContext)

    Swag.require(ctxSharedReadContext() == 42)
    Swag.require(ctxSharedContextMarker() == Swag.getContext().user2)
}

// Source dependencies leave no sibling libraries.
#test
{
    let artifactDir = Path.directoryName(Env.executablePath())
    Swag.require(artifactDir != null)

    let extension = #os == Swag.TargetOs.Windows ? ".dll" : ".so"
    let libraries = expect Directory.enumerateFiles(artifactDir, extension)
    Swag.require(libraries.count == 0)
}
