#global #if #command == Swag.CompilerCommand.Test
#global private
#global #[Swag.ExplicitNullability]
using Swag

private func makeWheelWParam(delta: u32)->u64
{
    return cast(u64) delta << 16
}

#test
{
    @assert(GET_WHEEL_DELTA_WPARAM(makeWheelWParam(0x0078)) == WHEEL_DELTA)
    @assert(GET_WHEEL_DELTA_WPARAM(makeWheelWParam(0xFF88)) == -WHEEL_DELTA)
    @assert(GET_WHEEL_DELTA_WPARAM(makeWheelWParam(0xFF10)) == -240)
}
