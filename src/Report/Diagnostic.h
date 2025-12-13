#pragma once
#include "Report/DiagnosticElement.h"
#include "Sema/Constant/ConstantValue.h"
#include "Sema/Type/TypeInfo.h"
#include "Wmf/SourceFile.h"

SWC_BEGIN_NAMESPACE()

class TaskContext;
enum class LogColor;
enum class DiagnosticId;
enum class TokenId : uint16_t;

class Diagnostic
{
public:
    struct Argument
    {
        std::string_view name;
        bool             quoted;

        std::variant<Utf8, TokenId, DiagnosticId, uint32_t, TypeRef, ConstantRef> val;
    };

private:
    std::vector<std::shared_ptr<DiagnosticElement>> elements_;
    std::vector<Argument>                           arguments_;
    FileRef                                         fileOwner_ = FileRef::invalid();
    bool                                            silent_    = false;

public:
    constexpr static std::string_view ARG_PATH             = "{path}";
    constexpr static std::string_view ARG_ARG              = "{arg}";
    constexpr static std::string_view ARG_COMMAND          = "{command}";
    constexpr static std::string_view ARG_VALUE            = "{value}";
    constexpr static std::string_view ARG_VALUES           = "{values}";
    constexpr static std::string_view ARG_LONG             = "{long}";
    constexpr static std::string_view ARG_SHORT            = "{short}";
    constexpr static std::string_view ARG_BEFORE           = "{before}";
    constexpr static std::string_view ARG_BECAUSE          = "{because}";
    constexpr static std::string_view ARG_TOK              = "{tok}";
    constexpr static std::string_view ARG_TOK_RAW          = "{tok-raw}";
    constexpr static std::string_view ARG_TOK_FAM          = "{tok-fam}";
    constexpr static std::string_view ARG_A_TOK_FAM        = "{a-tok-fam}";
    constexpr static std::string_view ARG_EXPECT_TOK       = "{expect-tok}";
    constexpr static std::string_view ARG_EXPECT_TOK_FAM   = "{expect-tok-fam}";
    constexpr static std::string_view ARG_EXPECT_A_TOK_FAM = "{expect-a-tok-fam}";
    constexpr static std::string_view ARG_PREV_TOK         = "{prev-tok}";
    constexpr static std::string_view ARG_PREV_TOK_FAM     = "{prev-tok-fam}";
    constexpr static std::string_view ARG_PREV_A_TOK_FAM   = "{prev-a-tok-fam}";
    constexpr static std::string_view ARG_NEXT_TOK         = "{next-tok}";
    constexpr static std::string_view ARG_NEXT_TOK_FAM     = "{next-tok-fam}";
    constexpr static std::string_view ARG_NEXT_A_TOK_FAM   = "{next-a-tok-fam}";
    constexpr static std::string_view ARG_TYPE             = "{type}";
    constexpr static std::string_view ARG_REQUESTED_TYPE   = "{requested-type}";
    constexpr static std::string_view ARG_LEFT             = "{left}";
    constexpr static std::string_view ARG_RIGHT            = "{right}";
    constexpr static std::string_view ARG_WHAT             = "{what}";

    Diagnostic() = default;
    explicit Diagnostic(FileRef file);
    Diagnostic(const Diagnostic&) = default;

    const std::vector<std::shared_ptr<DiagnosticElement>>& elements() const { return elements_; }
    FileRef                                                fileOwner() const { return fileOwner_; }
    const std::vector<Argument>&                           arguments() const { return arguments_; }
    void                                                   setSilent(bool silent) { silent_ = silent; }
    bool                                                   silent() const { return silent_; }

    DiagnosticElement& addElement(DiagnosticId id);
    DiagnosticElement& last() const { return *elements_.back(); }
    void               addArgument(std::string_view name, std::string_view arg, bool quoted = true);

    static Diagnostic         get(DiagnosticId id, FileRef file = FileRef::invalid());
    static std::string_view   diagIdMessage(DiagnosticId id);
    static std::string_view   diagIdName(DiagnosticId id);
    static DiagnosticSeverity diagIdSeverity(DiagnosticId id);

    static Utf8               tokenErrorString(const TaskContext& ctx, const SourceView& srcView, TokenRef tokRef);
    static SourceCodeLocation tokenErrorLocation(const TaskContext& ctx, const SourceView& srcView, TokenRef tokRef);

    template<typename T>
    void addArgument(std::string_view name, T&& arg, bool quoted = true)
    {
        arguments_.emplace_back(Argument{name, quoted, std::forward<T>(arg)});
    }

    void report(TaskContext& ctx) const;
};

SWC_END_NAMESPACE()
