#pragma once
#include "Lexer/Lexer.h"
#include "Lexer/SourceCodeLocation.h"
#include "Report/DiagnosticDef.h"

SWC_BEGIN_NAMESPACE()

class TaskContext;
class Global;
class Diagnostic;
struct SourceTrivia;

struct VerifyDirective
{
    DiagnosticSeverity kind = DiagnosticSeverity::Zero;
    Utf8               match;
    SourceCodeLocation loc;   // Location to raise the error
    SourceCodeLocation myLoc; // Location of the directive itself
    mutable bool       touched = false;
};

enum class VerifyFlagsE : uint32_t
{
    Zero    = 0,
    LexOnly = 1 << 0,
};
using VerifyFlags = EnumFlags<VerifyFlagsE>;

class Verify
{
    SourceFile*                  file_ = nullptr;
    SourceView                   srcView_;
    std::vector<VerifyDirective> directives_;
    VerifyFlags                  flags_ = VerifyFlagsE::Zero;

    void tokenizeOption(const TaskContext& ctx, std::string_view comment);
    void tokenizeExpected(const TaskContext& ctx, const SourceTrivia& trivia, std::string_view comment);

public:
    explicit Verify(SourceFile* file) :
        file_(file)
    {
    }

    void tokenize(TaskContext& ctx);
    bool hasFlag(VerifyFlagsE flag) const { return flags_.has(flag); }
    bool verifyExpected(const TaskContext& ctx, const Diagnostic& diag) const;
    void verifyUntouchedExpected(const TaskContext& ctx, const SourceView& srcView) const;
};

SWC_END_NAMESPACE()
