#global public

func moduleValue()->s32 => 41

namespace Helpers
{
    func viaModule()->s32 => Jit.moduleValue() + 1
}

#test
{
    @assert(Jit.moduleValue() == 41)
    @assert(Jit.Helpers.viaModule() == 42)
}
