#pragma once
#include "Report/DiagnosticElement.h"

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
    void               log(const DiagReporter& reporter, Logger& logger) const;
    DiagnosticElement* addElement(DiagnosticKind kind, DiagnosticId id);
};
