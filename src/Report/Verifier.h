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
};

class Verifier
{
    std::vector<VerifierDirective> directives_;

public:
    Result tokenize(const CompilerInstance& ci, const CompilerContext& ctx);
    bool   verify(const CompilerInstance& ci, const Diagnostic& diag);
};
