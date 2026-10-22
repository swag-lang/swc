#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

// The x64 ABI pads pointer fields after the DWORD members of the layered-window descriptor.
#test
{
    Swag.assert(#sizeof(UPDATELAYEREDWINDOWINFO) == 80)
    Swag.assert(#offsetof(UPDATELAYEREDWINDOWINFO.hdcDst) == 8)
    Swag.assert(#offsetof(UPDATELAYEREDWINDOWINFO.pblend) == 56)
    Swag.assert(#offsetof(UPDATELAYEREDWINDOWINFO.prcDirty) == 72)
}

func makeWheelWParam(delta: u32)->u64 => cast(u64, delta) << 16

#test
{
    Swag.assert(GET_WHEEL_DELTA_WPARAM(makeWheelWParam(0x0078)) == WHEEL_DELTA)
    Swag.assert(GET_WHEEL_DELTA_WPARAM(makeWheelWParam(0xFF88)) == -WHEEL_DELTA)
    Swag.assert(GET_WHEEL_DELTA_WPARAM(makeWheelWParam(0xFF10)) == -240)
}
