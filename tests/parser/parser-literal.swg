enum A { B = 1's8, }
enum A { B = 1's16, }
enum A { B = 1's32, }
enum A { B = 1's64, }
enum A { B = 1'u8, }
enum A { B = 1'u16, }
enum A { B = 1'u32, }
enum A { B = 1'u64, }
enum A { B = 1'f32, }
enum A { B = 1'f64, }
enum A { B = 1'T, }
enum A { B = 1'TTT_TTT, }
enum A { B = 1'bool, }
enum A { B = 1'rune, }

enum A { B = 1' } // swc-expected-error {{ParserEmptyLiteralSuffix}}
enum A { B = 1', } // swc-expected-error {{ParserEmptyLiteralSuffix}}

enum A { B = 1'any } // swc-expected-error {{ParserInvalidLiteralSuffix}}
enum A { B = 1'string } // swc-expected-error {{ParserInvalidLiteralSuffix}}
enum A { B = 1'cstring } // swc-expected-error {{ParserInvalidLiteralSuffix}}
enum A { B = 1'cvarargs } // swc-expected-error {{ParserInvalidLiteralSuffix}}
enum A { B = 1'typeinfo } // swc-expected-error {{ParserInvalidLiteralSuffix}}
enum A { B = 1'void } // swc-expected-error {{ParserInvalidLiteralSuffix}}