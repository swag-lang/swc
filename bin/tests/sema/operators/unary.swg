#global fileprivate

#assert(+1 == 1)
#assert(+1 == +1)
#assert(125 == +125)
#assert(+0 == 0)
#assert(+3.14 == 3.14)

#assert(~0 == -1)
#assert(~1 == -2)
#assert(~2 == -3)
#assert(~255 == -256)
#assert(~(-1) == 0)
#assert(~(-256) == 255)
#assert(~127's8 == -128)     // Boundary test for 8-bit signed

#assert(-1 == -1)
#assert(-(-1) == 1)
#assert(-(-1) == +1)
#assert(-10's8 == -10)
#assert(-0 == 0)
#assert(-0.0 == 0.0)
#assert(-1.0 == -1.0)
#assert(-(-3.5) == 3.5)

#assert(-128's8 == -128)

#assert(!true == false)
#assert(!false == true)

#assert(!false)
#assert(!(!false == false))
#assert(!(!true == true))

#assert(!(1 == 2))
#assert(!("1" == "2"))
#assert(!1 == false)
#assert(!0 == true)
