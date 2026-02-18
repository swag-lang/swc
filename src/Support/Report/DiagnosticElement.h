#pragma once
#include "Compiler/Lexer/SourceCodeRange.h"
#include "Compiler/Lexer/Token.h"
#include "Support/Report/DiagnosticDef.h"

SWC_BEGIN_NAMESPACE();

class SourceFile;
class TaskContext;
enum class DiagnosticId;

struct DiagnosticArgument
{
    std::string_view name;

    std::variant<Utf8,
                 TokenId,
                 DiagnosticId,
                 uint32_t,
                 int64_t,
                 uint64_t,
                 TypeRef,
                 ConstantRef,
                 IdentifierRef>
        val;
};

using DiagnosticArguments = std::vector<DiagnosticArgument>;

class DiagnosticElement
{
public:
    explicit DiagnosticElement(DiagnosticId id);
    explicit DiagnosticElement(DiagnosticSeverity severity, DiagnosticId id);

    void              setSrcView(const SourceView* srcView) { srcView_ = srcView; }
    const SourceView* srcView() const { return srcView_; }

    void                               addSpan(const SourceView* srcView, uint32_t offset, uint32_t len, DiagnosticSeverity severity = DiagnosticSeverity::Zero, const Utf8& message = Utf8());
    void                               addSpan(const SourceCodeRange& codeRange, const Utf8& message = "", DiagnosticSeverity severity = DiagnosticSeverity::Zero);
    void                               addSpan(const SourceCodeRange& codeRange, DiagnosticId diagId, DiagnosticSeverity severity = DiagnosticSeverity::Zero);
    const std::vector<DiagnosticSpan>& spans() const { return spans_; }
    DiagnosticSpan&                    span(uint32_t index) { return spans_[index]; }
    const DiagnosticSpan&              span(uint32_t index) const { return spans_[index]; }
    bool                               hasSpans() const { return srcView_ != nullptr && !spans_.empty(); }

    Utf8 message() const;
    void setMessage(Utf8 m);

    SourceCodeRange    codeRange(uint32_t spanIndex, const TaskContext& ctx) const;
    SourceCodeRange    codeRange(const DiagnosticSpan& span, const TaskContext& ctx) const;
    std::string_view   idName() const;
    DiagnosticId       id() const { return id_; }
    DiagnosticSeverity severity() const { return severity_; }
    void               setSeverity(DiagnosticSeverity sev) { severity_ = sev; }
    bool               isNoteOrHelp() const;

    const DiagnosticArguments& arguments() const { return arguments_; }
    void                       addArgument(std::string_view name, std::string_view arg);

    template<typename T>
    void addArgument(std::string_view name, T&& arg)
    {
        arguments_.emplace_back(DiagnosticArgument{name, std::forward<T>(arg)});
    }

private:
    Utf8                        message_;
    DiagnosticId                id_;
    DiagnosticSeverity          severity_;
    const SourceView*           srcView_ = nullptr;
    std::vector<DiagnosticSpan> spans_;
    DiagnosticArguments         arguments_;
};

SWC_END_NAMESPACE();
