#pragma once
#include "Lexer/SourceCodeLocation.h"

SWC_BEGIN_NAMESPACE()

class TaskContext;
class Global;
enum class DiagnosticSeverity;
struct LexTrivia;
class Diagnostic;

struct UnitTestDirective
{
    DiagnosticSeverity kind;
    Utf8               match;
    SourceCodeLocation loc;   // Location to raise the error
    SourceCodeLocation myLoc; // Location of the directive itself
    mutable bool       touched = false;
};

class UnitTest
{
    SourceFile*                    file_;
    std::vector<UnitTestDirective> directives_;

    static void tokenizeOption(TaskContext& ctx, std::string_view comment);
    void        tokenizeExpected(const TaskContext& ctx, const LexTrivia& trivia, std::string_view comment);

public:
    explicit UnitTest(SourceFile* file) :
        file_(file)
    {
    }

    Result tokenize(TaskContext& ctx);
    bool   verifyExpected(const TaskContext& ctx, const Diagnostic& diag) const;
    Result verifyUntouchedExpected(const TaskContext& ctx) const;
};

SWC_END_NAMESPACE()
