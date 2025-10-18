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

#define SWAG_DIAG(__id, __txt) __txt,
inline const char* g_DiagnosticIdMessages[] =
{
#include "Report/DiagnosticList.h"
};
#undef SWAG_DIAG

class DiagReporter
{
public:
    static std::unique_ptr<Diagnostic> diagnostic(DiagnosticId id);
    void                               report(CompilerInstance& ci, CompilerContext &ctx, Diagnostic& diag);
};
