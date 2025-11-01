enum A } // swc-expected-error ParserExpectedTokenAfter
enum A toto } // swc-expected-error ParserExpectedTokenAfter

enum A { B C } // swc-expected-error ParserExpectedToken
enum  { } // swc-expected-error ParserExpectedTokenFamAfter
enum enum { } // swc-expected-error ParserExpectedTokenFamAfter
enum #ast { } // swc-expected-error ParserExpectedTokenFamAfter
enum A B { C } // swc-expected-error ParserExpectedTokenAfter
enum A { B,, C } // swc-expected-error ParserExpectedToken

enum A
{
    B = 0
    C = 1
}

enum A { B, C }
enum A { B, C, }

enum A
{
    B,
    C,
}

enum A
{
    B
    C
}

enum
A
{
    B
    C
}

enum A
{
    B = 0,
    C = 1,
}

enum A : B { B = 0, C = 1, }


