// ============================================================================
// Parser Attributes Error
// ============================================================================

#[] // swc-expected-error {{ParserEmptyAttribute}}
enum B {}

#[A(] // swc-expected-error {{ParserUnexpectedToken}} {{ParserExpectedClosing}}
enum B {}

#[A // swc-expected-error {{ParserExpectedClosing}}
enum B {} // swc-expected-error {{ParserExpectedTokenBefore}}