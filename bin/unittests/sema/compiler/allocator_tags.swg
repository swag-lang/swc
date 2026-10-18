#global private

var cfg: Swag.Build.Config

#assert(#defined(cfg.allocatorCaptureStack) == #hastag("Swag.AllocatorDiagnostics"))
#assert(#defined(cfg.allocatorLeaks) == #hastag("Swag.AllocatorDiagnostics"))
#assert(#defined(cfg.allocatorTrackAllocations) == #hastag("Swag.AllocatorDiagnostics"))
#assert(#defined(cfg.allocatorElectricMode) == #hastag("Swag.AllocatorDiagnostics"))
#assert(#defined(cfg.allocatorFillMemory) == #hastag("Swag.AllocatorDiagnostics"))

#assert(#gettag("Swag.AllocatorSafety", bool, false) == #hastag("Swag.AllocatorSafety"))
#assert(#gettag("Swag.AllocatorDiagnostics", bool, false) == #hastag("Swag.AllocatorDiagnostics"))

#static if #hastag("Swag.AllocatorDiagnostics")
{
    #assert(#typeof(cfg.allocatorCaptureStack) == bool)
    #assert(#typeof(cfg.allocatorLeaks) == bool)
    #assert(#typeof(cfg.allocatorTrackAllocations) == bool)
    #assert(#typeof(cfg.allocatorElectricMode) == bool)
    #assert(#typeof(cfg.allocatorFillMemory) == bool)
}
