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
    addError(DiagnosticId::CannotOpenFile, "failed to open file %0");
    addError(DiagnosticId::CannotReadFile, "failed to read file %0");
    addError(DiagnosticId::FileNotUtf8, "source file %0 is not utf8");
    addError(DiagnosticId::UnclosedComment, "unclose multi-line comment");
}
