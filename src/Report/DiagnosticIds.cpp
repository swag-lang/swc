#include "pch.h"

#include "Report/DiagnosticIds.h"

DiagnosticIds::DiagnosticIds()
{
    initErrors();
}

std::string_view DiagnosticIds::diagMessage(DiagnosticId id) const
{
    SWAG_ASSERT(static_cast<size_t>(id) < infos_.size());
    return infos_[static_cast<size_t>(id)].msg;
}

std::string_view DiagnosticIds::diagName(DiagnosticId id) const
{
    SWAG_ASSERT(static_cast<size_t>(id) < infos_.size());
    return infos_[static_cast<size_t>(id)].name;
}

void DiagnosticIds::addId(DiagnosticId id, const std::string_view name, std::string_view msg)
{
    const auto index = static_cast<size_t>(id);
    if (index >= infos_.size())
        infos_.resize(index + 1);
    infos_[index] = {.id = id, .name = name, .msg = msg};
}

void DiagnosticIds::initErrors()
{
#define SWAG_DIAG(id, msg) addId(DiagnosticId::id, #id, msg);

    SWAG_DIAG(CannotOpenFile, "failed to open file");
    SWAG_DIAG(CannotReadFile, "failed to read file");
    SWAG_DIAG(FileNotUtf8, "source file is not utf8");
    SWAG_DIAG(UnclosedComment, "unclosed multi-line comment");
    SWAG_DIAG(StringLiteralEol, "invalid eol in string");
    SWAG_DIAG(UnclosedStringLiteral, "unclosed string literal");
    SWAG_DIAG(NumberSepMulti, "a number cannot have multiple consecutive '_'");
    SWAG_DIAG(NumberSepStart, "a number cannot start with '_'");   
    SWAG_DIAG(NumberSepEnd, "a number cannot end with '_'");
    SWAG_DIAG(MissingHexDigits, "missing hexadecimal digits");
    SWAG_DIAG(MissingBinDigits, "missing binary digits");
    SWAG_DIAG(MissingExponentDigits, "missing exponent digit");
    SWAG_DIAG(SyntaxHexNumber, "malformed hexadecimal number");
    SWAG_DIAG(SyntaxBinNumber, "malformed binary number");
    SWAG_DIAG(UnRaisedDirective, "unraised directive");
    SWAG_DIAG(InvalidEscapeSequence, "invalid escape sequence");
    SWAG_DIAG(InvalidCharacter, "invalid character");
    SWAG_DIAG(EmptyCharLiteral, "");
    SWAG_DIAG(UnclosedCharLiteral, "");
    SWAG_DIAG(CharLiteralEol, "");
    SWAG_DIAG(TooManyCharsInLiteral, "");
    SWAG_DIAG(InvalidHexDigits, "");
    SWAG_DIAG(IncompleteHexEscape, "");
}
