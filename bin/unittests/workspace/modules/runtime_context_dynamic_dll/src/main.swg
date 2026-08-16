#global public

using Core

// Calls into an imported module that raises, then catches that failure back in this DLL.
func ctxDynamicCatchesCoreFailure()->bool
{
    discard catch File.info("C:/swag-dynamic-runtime-context-missing-file") as raised
    return raised != null
}
