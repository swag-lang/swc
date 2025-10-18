#pragma once
#include "Diagnostic.h"

enum class DiagnosticKind;
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
    static std::unique_ptr<Diagnostic> diagnostic(DiagnosticKind kind, DiagnosticId id);
    static std::unique_ptr<Diagnostic> error(DiagnosticId id) { return diagnostic(DiagnosticKind::Error, id); }
    static std::unique_ptr<Diagnostic> warning(DiagnosticId id) { return diagnostic(DiagnosticKind::Warning, id); }
    static std::unique_ptr<Diagnostic> note(DiagnosticId id) { return diagnostic(DiagnosticKind::Note, id); }
    static std::unique_ptr<Diagnostic> hint(DiagnosticId id) { return diagnostic(DiagnosticKind::Hint, id); }

    static std::string_view diagnosticMessage(DiagnosticId id);

    void report(CompilerInstance& ci, const CompilerContext& ctx, Diagnostic& diag);
};
