// ============================================================================
// Parser Misc Ok
// ============================================================================

#error(B)
#warning(B)
#print(C)

#assert(#sizeof(MyStruct1) == 9)
#assert(#sizeof(MyStruct1.A.B.C) == 9)
#assert(#sizeof(MyStruct1.A.B.C as s32) == 9)
#assert(#sizeof(MyStruct1.A.B.C is s32) == 9)

#if A { } #else { }

#assert(A == 5)
