#pragma once
#include "Report/DiagnosticElement.h"
#include "Report/DiagnosticIds.h"

class CompilerContext;
class CompilerInstance;
enum class DiagnosticId;

enum class DiagnosticKind
{
    Error,
    Warning,
    Note,
    Hint,
};

class Logger;

class Diagnostic
{
    std::vector<std::unique_ptr<DiagnosticElement>> elements_;

public:
    Result report(const CompilerInstance& ci) const;

    DiagnosticElement* addElement(DiagnosticKind kind, DiagnosticId id);
    DiagnosticElement* addError(DiagnosticId id) { return addElement(DiagnosticKind::Error, id); }
};
