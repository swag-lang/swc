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

    static void tokenizeOption(const Context& ctx, const TriviaSpan& trivia, std::string_view comment);
    void        tokenizeExpected(const Context& ctx, const TriviaSpan& trivia, std::string_view comment);

public:
    Result tokenize(Context& ctx);
    bool   verifyExpected(const Context& ctx, const Diagnostic& diag) const;
    Result verifyExpected(const Context& ctx) const;
};

SWC_END_NAMESPACE();
