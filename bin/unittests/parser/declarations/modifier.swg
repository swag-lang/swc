#global private

#assert(cast #bit (s32) 9)
#assert(cast #unconst (s32) 9)
#assert(cast #fail (s32) 9)
#assert(cast #nofail (s32) 9)
#assert(cast #prom (s32) 9)
#assert(cast #wrap (s32) 9)
#assert(cast #nodrop (s32) 9)
#assert(cast #move (s32) 9)
#assert(cast #relocate (s32) 9)
#assert(cast (s32?) 9)

#assert(cast #bit #unconst (s32) 9)
#assert(cast #bit #unconst #fail (s32) 9)
