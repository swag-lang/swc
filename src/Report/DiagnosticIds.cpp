#include "pch.h"

#include "Report/Reporter.h"

void Reporter::addError(DiagnosticId id, std::string_view msg)
{
    const auto index = static_cast<size_t>(id);
    if (index >= diagMsgs_.size())
        diagMsgs_.resize(index + 1);
    diagMsgs_[index] = msg;
}

void Reporter::initErrors()
{
    addError(DiagnosticId::CannotOpenFile, "failed to open file");
    addError(DiagnosticId::CannotReadFile, "failed to read file");
    addError(DiagnosticId::FileNotUtf8, "source file is not utf8");
    addError(DiagnosticId::UnclosedComment, "unclosed multi-line comment");
    addError(DiagnosticId::EolInStringLiteral, "invalid eol in string");
    addError(DiagnosticId::UnclosedStringLiteral, "unclosed string literal");
    addError(DiagnosticId::SyntaxNumberSepMulti, "a number cannot have multiple consecutive '_'");
    addError(DiagnosticId::SyntaxNumberSepAtEnd, "a number cannot have '_' at the end");
    addError(DiagnosticId::SyntaxMissingHexDigits, "missing hex digits");
    addError(DiagnosticId::SyntaxMalformedHexNumber, "malformed hex number");
}
