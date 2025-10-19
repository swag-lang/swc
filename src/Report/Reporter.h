#pragma once
#include "Diagnostic.h"

enum class DiagnosticKind;
class CompilerContext;
class CompilerInstance;
class Diagnostic;

class Reporter
{
public:
    Reporter();
    
    std::string_view diagMessage(DiagnosticId id) const;

    static void report(const CompilerInstance& ci, const CompilerContext& ctx, const Diagnostic& diag);

private:
    std::vector<std::string_view> diagMsgs_;

    void addError(DiagnosticId id, std::string_view msg);
    void initErrors();
};
