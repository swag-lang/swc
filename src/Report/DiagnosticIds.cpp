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

void DiagnosticIds::addId(DiagnosticId id, const std::string_view name)
{
    const auto index = static_cast<size_t>(id);
    if (index >= infos_.size())
        infos_.resize(index + 1);
    infos_[index] = {.id = id, .name = name};
}

void DiagnosticIds::initErrors()
{
#define SWAG_DIAG(id) addId(DiagnosticId::id, #id);

    SWAG_DIAG(CannotOpenFile);
    SWAG_DIAG(CannotReadFile);

    SWAG_DIAG(UnRaisedDirective);
    
    SWAG_DIAG(FileNotUtf8);
    
    SWAG_DIAG(UnclosedComment);
    SWAG_DIAG(NewlineInStringLiteral);
    SWAG_DIAG(UnclosedStringLiteral);
    SWAG_DIAG(ConsecutiveNumberSeparators);
    SWAG_DIAG(LeadingNumberSeparator);   
    SWAG_DIAG(TrailingNumberSeparator);
    SWAG_DIAG(MissingHexDigits);
    SWAG_DIAG(MissingBinDigits);
    SWAG_DIAG(MissingExponentDigits);
    SWAG_DIAG(InvalidHexNumberSuffix);
    SWAG_DIAG(InvalidBinNumberSuffix);
    SWAG_DIAG(InvalidEscapeSequence);
    SWAG_DIAG(InvalidCharacter);
    SWAG_DIAG(EmptyCharLiteral);
    SWAG_DIAG(UnclosedCharLiteral);
    SWAG_DIAG(InvalidHexDigit);
    SWAG_DIAG(IncompleteHexEscape);
    SWAG_DIAG(EmptyHexEscape);
}
