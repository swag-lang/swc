#pragma once

class CompilerContext;
class CompilerInstance;
enum class DiagnosticKind;

struct VerifierDirective
{
    DiagnosticKind   kind;
    std::string_view match;
};

class Verifier
{
    std::vector<VerifierDirective> directives_;

public:
    Result tokenize(const CompilerInstance& ci, const CompilerContext& ctx);
};
