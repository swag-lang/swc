#pragma once
#include "Diagnostic.h"

enum class DiagnosticKind;
class CompilerContext;
class CompilerInstance;
class Diagnostic;

class DiagReporter
{
public:
    DiagReporter();
    static std::unique_ptr<Diagnostic> diagnostic();
    
    std::string_view diagMessage(DiagnosticId id) const;

    void report(CompilerInstance& ci, const CompilerContext& ctx, Diagnostic& diag);

private:
    std::vector<std::string_view> diagMsgs_;

    void initErrors();
};
