#pragma once
#include "Lexer/SourceCodeLocation.h"

class CompilerContext;
class CompilerInstance;
enum class DiagnosticKind;

struct VerifierDirective
{
    DiagnosticKind     kind;
    Utf8               match;
    SourceCodeLocation location;
    mutable bool       touched = false;
};

class Verifier
{
    std::vector<VerifierDirective> directives_;

public:
    Result tokenize(CompilerContext& ctx);
    bool   verify(CompilerContext& ctx, const Diagnostic& diag) const;
    Result verify(CompilerContext& ctx) const;
};
