#pragma once

enum class DiagnosticId
{
    CannotOpenFile,
    CannotReadFile,
    FileNotUtf8,
    UnclosedComment,
    StringLiteralEol,
    UnclosedStringLiteral,
    NumberSepMulti,
    NumberSepStart,
    NumberSepEnd,
    MissingHexDigits,
    MissingBinDigits,
    MissingExponentDigits,
    SyntaxHexNumber,
    SyntaxBinNumber,
    UnRaisedDirective,
    InvalidEscapeSequence,
    InvalidCharacter,
    EmptyCharLiteral,
    UnclosedCharLiteral,
    CharLiteralEol,
    TooManyCharsInLiteral,
    InvalidHexDigit,
    IncompleteHexEscape,
};

struct DiagnosticIdInfo
{
    DiagnosticId     id;
    std::string_view name;
    std::string_view msg;
};

class DiagnosticIds
{
public:
    DiagnosticIds();

    std::string_view diagMessage(DiagnosticId id) const;
    std::string_view diagName(DiagnosticId id) const;

private:
    std::vector<DiagnosticIdInfo> infos_;

    void addId(DiagnosticId id, std::string_view name);
    void initErrors();
};
