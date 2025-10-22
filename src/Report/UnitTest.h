#pragma once
#include "Lexer/SourceCodeLocation.h"

class CompilerContext;
class CompilerInstance;
enum class DiagnosticSeverity;

struct VerifierDirective
{
    DiagnosticSeverity     kind;
    Utf8               match;
    SourceCodeLocation loc;   // Location to raise the error
    SourceCodeLocation myLoc; // Location of the directive itself
    mutable bool       touched = false;
};

class UnitTest
{
    std::vector<VerifierDirective> directives_;

public:
    Result tokenize(CompilerContext& ctx);
    bool   verify(const Diagnostic& diag) const;
    Result verify(CompilerContext& ctx) const;
};
