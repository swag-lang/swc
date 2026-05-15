#global public

fileprivate const CollisionValue = 41
fileprivate func collisionHelper()->s32 => CollisionValue

#test
{
    @assert(collisionHelper() == 41)
}
