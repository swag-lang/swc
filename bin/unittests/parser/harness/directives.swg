#global private

#error(B)
#warning(B)
#print(C)

#assert(#sizeof(MyStruct1) == 9)
#assert(#sizeof(MyStruct1.A.B.C) == 9)
#assert(#sizeof(cast #assume (s32) MyStruct1.A.B.C) == 9)
#assert(#sizeof(cast #try (*s32) MyStruct1.A.B.C != null) == 9)

#static if A { } else { }

#assert(A == 5)

using A
#assert(A == 5)
