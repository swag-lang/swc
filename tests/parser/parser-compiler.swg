enum A
{
    #assert(A)
    B,
    C,
}

#assert A // swc-expected-error {{ParserExpectedToken}}
// swc-expected-error@+ {{ParserExpectedClosing}}
#assert(A)
#assert(A) #assert(A) // swc-expected-error {{ParserExpectedEndOfLine}}

#error(B)
#warning(B)
#print(C)

#assert(#sizeof(MyStruct1) == 9)
#assert(#sizeof(MyStruct1.A.B.C) == 9)
#assert(#sizeof(MyStruct1.A.B.C as s32) == 9)