enum  { } // swc-expected-error ParserExpectedTokenFamAfter
enum enum { } // swc-expected-error ParserExpectedTokenFamAfter
enum #ast { } // swc-expected-error ParserExpectedTokenFamAfter
enum A } // swc-expected-error ParserExpectedTokenAfter
enum A toto } // swc-expected-error ParserExpectedTokenAfter
enum A A { C } // swc-expected-error ParserExpectedTokenAfter

enum A { B B }
/*enum A { B, C }
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
enum A
{
    B = 0,
    C = 1,
}
enum A : B { B = 0, C = 1, }*/