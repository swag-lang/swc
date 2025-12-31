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

    // Line constraint:
    // - if lineMin == 0 and lineMax == 0 and allowedLines empty => "anywhere" (@*)
    // - if allowedLines not empty => match any line in the set
    // - else match inclusive [lineMin, lineMax]
    uint32_t              lineMin = 0;
    uint32_t              lineMax = 0;
    std::vector<uint32_t> allowedLines;

    mutable bool touched = false;

    bool matchesLine(uint32_t line) const noexcept
    {
        // "anywhere" => both 0
        if (lineMin == 0 && lineMax == 0 && allowedLines.empty())
            return true;

        // explicit list wins
        if (!allowedLines.empty())
        {
            for (const uint32_t ln : allowedLines)
            {
                if (ln == line)
                    return true;
            }
            return false;
        }

        // range / exact
        return line >= lineMin && line <= lineMax;
    }
};

enum class VerifyFlagsE : uint32_t
{
    Zero    = 0,
    LexOnly = 1 << 0,
};
using VerifyFlags = EnumFlags<VerifyFlagsE>;

class Verify
{
public:
    explicit Verify(SourceFile* file) :
        file_(file)
    {
    }

    void tokenize(TaskContext& ctx);
    bool hasFlag(VerifyFlagsE flag) const { return flags_.has(flag); }
    bool verifyExpected(const TaskContext& ctx, const Diagnostic& diag) const;
    void verifyUntouchedExpected(TaskContext& ctx, const SourceView& srcView) const;

private:
    SourceFile*                  file_    = nullptr;
    SourceView*                  srcView_ = nullptr;
    std::vector<VerifyDirective> directives_;
    VerifyFlags                  flags_ = VerifyFlagsE::Zero;

    void tokenizeOption(const TaskContext& ctx, std::string_view comment);
    void tokenizeExpected(const TaskContext& ctx, const SourceTrivia& trivia, std::string_view comment);
};

SWC_END_NAMESPACE()
