// ============================================================================
// Parser Attributes Error
// ============================================================================

#[] // swc-expected-error {{ParserEmptyAttribute}}
enum B {}

#[A(] // swc-expected-error {{ParserUnexpectedToken}} {{ParserExpectedTokenAfter}}
enum B {}

#[A // swc-expected-error {{ParserExpectedClosing}} {{ParserExpectedTokenAfter}}
enum B {}