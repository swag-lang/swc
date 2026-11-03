#global public

func moduleValue()->s32 => 41

namespace Helpers
{
    func viaModule()->s32 => Jit.moduleValue() + 1
}

#test
{
    Swag.require(Jit.moduleValue() == 41)
    Swag.require(Jit.Helpers.viaModule() == 42)
}
