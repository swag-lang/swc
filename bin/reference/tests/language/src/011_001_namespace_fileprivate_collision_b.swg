#global public

fileprivate const CollisionValue = 12
fileprivate func collisionHelper()->s32 => CollisionValue

#test
{
    @assert(collisionHelper() == 12)
}
