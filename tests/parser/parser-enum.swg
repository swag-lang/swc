enum  { } // swc-expected-error ParserExpectedTokenFamAfter
enum enum { } // swc-expected-error ParserExpectedTokenFamAfter
enum #ast { } // swc-expected-error ParserExpectedTokenFamAfter
enum A } // swc-expected-error ParserExpectedTokenAfter
enum A toto } // swc-expected-error ParserExpectedTokenAfter
