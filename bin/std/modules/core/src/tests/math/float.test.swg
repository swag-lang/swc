#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

#test
{
    @assert(Math.saturate(-2'f32) == 0'f32)
    @assert(Math.saturate(2'f32) == 1'f32)
    @assert(Math.lerp(2'f32, 10'f32, 0.25'f32) == 4'f32)
    @assert(Math.moveTowards(0'f32, 10'f32, 3'f32) == 3'f32)
    @assert(Math.moveTowards(8'f32, 10'f32, 3'f32) == 10'f32)
    @assert(Math.isEqualEpsilon(Math.toDegrees(Math.ConstF32.Pi), 180'f32, 0.001'f32))
}
