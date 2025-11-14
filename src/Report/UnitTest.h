#pragma once
#include "Lexer/Lexer.h"
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

enum class UnitTestFlagsE : uint32_t
{
    Zero    = 0,
    LexOnly = 1 << 0,
};
using UnitTestFlags = EnumFlags<UnitTestFlagsE>;

class UnitTest
{
    LexerOutput                    lexOut_;
    UnitTestFlags                  flags_ = UnitTestFlagsE::Zero;
    std::vector<UnitTestDirective> directives_;

    void tokenizeOption(const TaskContext& ctx, std::string_view comment);
    void tokenizeExpected(const TaskContext& ctx, const LexTrivia& trivia, std::string_view comment);

public:
    void tokenize(TaskContext& ctx);
    bool hasFlag(UnitTestFlagsE flag) const { return flags_.has(flag); }
    bool verifyExpected(const TaskContext& ctx, const Diagnostic& diag) const;
    void verifyUntouchedExpected(const TaskContext& ctx) const;
};

SWC_END_NAMESPACE()
