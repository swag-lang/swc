// @FAIL
#global skip
#global fileprivate
#assert(1 << 1)
#assert(1 << 2 == 4)
#assert(4 >> 1 == 2)
