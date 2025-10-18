#pragma once

class CompilerContext;
class CompilerInstance;
class Diagnostic;

#define SWAG_DIAG(__id, __txt) __id,
enum class DiagnosticId
{
#include "Report/DiagnosticList.h"
};
#undef SWAG_DIAG

class DiagReporter
{
public:
    static std::unique_ptr<Diagnostic> diagnostic(DiagnosticId id);

    static std::string_view diagnosticMessage(DiagnosticId id);

    void report(CompilerInstance& ci, CompilerContext& ctx, Diagnostic& diag);
};
