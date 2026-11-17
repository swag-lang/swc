#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    Swag.require(Math.isNaN(Math.Vector2.Zero.angleCosineTo(Math.Vector2.UnitX)))
    Swag.require(Math.isNaN(Math.Vector2.UnitX.angleTo(Math.Vector2.Zero)))
    Swag.require(Math.isNaN(Math.Vector2.Zero.orientedAngleTo(Math.Vector2.UnitY)))

    Swag.require(Math.isNaN(Math.Vector3.Zero.angleCosineTo(Math.Vector3.UnitX)))
    Swag.require(Math.isNaN(Math.Vector3.UnitX.angleTo(Math.Vector3.Zero)))

    Swag.require(Math.isNaN(Math.Vector4.Zero.angleCosineTo(Math.Vector4.UnitX)))
    Swag.require(Math.isNaN(Math.Vector4.UnitX.angleTo(Math.Vector4.Zero)))
}
