#global internal

#assert(#file == #file)
#assert(#line == 4)
#assert(#line ++ 3's32 == "53")
#assert(#line ++ 3 == "63")
#assert(#swcversion == #swcversion)
#assert(#swcrevision == #swcrevision)
#assert(#swcrevision > 0)
#assert(#swcbuildnum == #swcbuildnum)
#assert(#swcbuildnum > 0)
