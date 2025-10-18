#pragma once

class Diagnostic;

#define SWAG_DIAG(__id, __txt) __id,
enum class DiagnosticId
{
#include "Report/DiagnosticList.h"
};

class DiagReporter
{
public:
    static std::unique_ptr<Diagnostic> diagnostic(DiagnosticId id);
    void                               report(const std::unique_ptr<Diagnostic>& diag);
};
