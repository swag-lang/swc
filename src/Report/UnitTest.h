#pragma once
#include "Lexer/SourceCodeLocation.h"

SWC_BEGIN_NAMESPACE();

class Context;
class Global;
enum class DiagnosticSeverity;

struct VerifierDirective
{
    DiagnosticSeverity kind;
    Utf8               match;
    SourceCodeLocation loc;   // Location to raise the error
    SourceCodeLocation myLoc; // Location of the directive itself
    mutable bool       touched = false;
};

class UnitTest
{
    std::vector<VerifierDirective> directives_;

public:
    Result tokenize(Context& ctx);
    bool   verify(const Context& ctx, const Diagnostic& diag) const;
    Result verify(Context& ctx) const;
};

SWC_END_NAMESPACE();
