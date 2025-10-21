#pragma once

enum class DiagnosticId
{
    CmdLineInvalidEnumValue,
    
    CannotOpenFile,
    CannotReadFile,
    
    FileNotUtf8,
    
    UnclosedComment,
    NewlineInStringLiteral,
    UnclosedStringLiteral,
    ConsecutiveNumberSeparators,
    LeadingNumberSeparator,
    TrailingNumberSeparator,
    MissingHexDigits,
    MissingBinDigits,
    MissingExponentDigits,
    InvalidHexNumberSuffix,
    InvalidBinNumberSuffix,
    UnRaisedDirective,
    InvalidEscapeSequence,
    InvalidCharacter,
    EmptyCharLiteral,
    UnclosedCharLiteral,
    InvalidHexDigit,
    IncompleteHexEscape,
    EmptyHexEscape,
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
