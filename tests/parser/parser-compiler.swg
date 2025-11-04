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
#assert(#sizeof(MyStruct1.A.B.C is s32) == 9)

#assert(cast(s32) #sizeof(MyStruct1) == 9)
#assert(#typeof(0's8 + 1's8) == s8)

#if A { } #else { }

enum A
{
    #if A do
        A = 0
    #else {
        A = 1
    }
}


enum A
{
    #if A do
        A = 0
    #else // swc-expected-error {{ParserExpectedDoOrBlock}}
        A = 1
}

enum A
{
    #if A == 0 do
        A = 0
    #else {
        A = 1
    }
}

