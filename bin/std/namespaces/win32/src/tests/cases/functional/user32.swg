#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

using Swag

// The x64 ABI pads pointer fields after the DWORD members of the layered-window descriptor.
#test
{
    Swag.require(#sizeof(UPDATELAYEREDWINDOWINFO) == 80)
    Swag.require(#offsetof(UPDATELAYEREDWINDOWINFO.hdcDst) == 8)
    Swag.require(#offsetof(UPDATELAYEREDWINDOWINFO.pblend) == 56)
    Swag.require(#offsetof(UPDATELAYEREDWINDOWINFO.prcDirty) == 72)
}

func makeWheelWParam(delta: u32)->u64 => cast(u64, delta) << 16

#test
{
    Swag.require(GET_WHEEL_DELTA_WPARAM(makeWheelWParam(0x0078)) == WHEEL_DELTA)
    Swag.require(GET_WHEEL_DELTA_WPARAM(makeWheelWParam(0xFF88)) == -WHEEL_DELTA)
    Swag.require(GET_WHEEL_DELTA_WPARAM(makeWheelWParam(0xFF10)) == -240)
}
