// ============================================================================
// Parser Enums Error
// ============================================================================

enum A
{
    #if A do
        A = 0
    #else // swc-expected-error {{ParserExpectedDoOrBlock}}
        A = 1
}

enum A } // swc-expected-error {{ParserExpectedTokenBefore}}
enum A toto } // swc-expected-error {{ParserExpectedTokenBefore}} {{UnexpectedToken}}

enum A { B C } // swc-expected-error {{ParserExpectedToken}}
enum  { } // swc-expected-error {{ParserExpectedTokenBeforeFam}}
enum enum { } // swc-expected-error {{ParserExpectedTokenBeforeFam}}
enum #ast { } // swc-expected-error {{ParserExpectedTokenBeforeFam}}
enum A B { C } // swc-expected-error {{ParserExpectedTokenBefore}}
enum A { B,, C } // swc-expected-error {{ParserUnexpectedToken}}

enum A { B = 1' } // swc-expected-error {{ParserEmptyLiteralSuffix}}
enum A { B = 1', } // swc-expected-error {{ParserEmptyLiteralSuffix}}

enum A { B = 1'any } // swc-expected-error {{ParserInvalidLiteralSuffix}}
enum A { B = 1'string } // swc-expected-error {{ParserInvalidLiteralSuffix}}
enum A { B = 1'cstring } // swc-expected-error {{ParserInvalidLiteralSuffix}}
enum A { B = 1'cvarargs } // swc-expected-error {{ParserInvalidLiteralSuffix}}
enum A { B = 1'typeinfo } // swc-expected-error {{ParserInvalidLiteralSuffix}}
enum A { B = 1'void } // swc-expected-error {{ParserInvalidLiteralSuffix}}
