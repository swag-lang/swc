#pragma once
#include "Report/DiagnosticElement.h"

SWC_BEGIN_NAMESPACE()

enum class LogColor;

class TaskContext;
enum class DiagnosticId;
enum class TokenId : uint16_t;

class Diagnostic
{
public:
    struct Argument
    {
        std::string_view name;
        bool             quoted;

        std::variant<Utf8, TokenId, DiagnosticId, uint32_t> val;
    };

private:
    std::vector<std::shared_ptr<DiagnosticElement>> elements_;
    std::vector<Argument>                           arguments_;
    std::optional<SourceFile*>                      fileOwner_ = std::nullopt;
    bool                                            silent_    = false;

public:
    constexpr static std::string_view ARG_PATH    = "{path}";
    constexpr static std::string_view ARG_ARG     = "{arg}";
    constexpr static std::string_view ARG_COMMAND = "{command}";
    constexpr static std::string_view ARG_VALUE   = "{value}";
    constexpr static std::string_view ARG_VALUES  = "{values}";
    constexpr static std::string_view ARG_LONG    = "{long}";
    constexpr static std::string_view ARG_SHORT   = "{short}";

    constexpr static std::string_view ARG_TOK            = "{tok}";
    constexpr static std::string_view ARG_TOK_FAM        = "{tok-fam}";
    constexpr static std::string_view ARG_A_TOK_FAM      = "{a-tok-fam}";
    constexpr static std::string_view ARG_EXPECT         = "{expect-tok}";
    constexpr static std::string_view ARG_EXPECT_FAM     = "{expect-tok-fam}";
    constexpr static std::string_view ARG_A_EXPECT_FAM   = "{expect-a-tok-fam}";
    constexpr static std::string_view ARG_PREV_TOK       = "{prev-tok}";
    constexpr static std::string_view ARG_PREV_TOK_FAM   = "{prev-tok-fam}";
    constexpr static std::string_view ARG_PREV_A_TOK_FAM = "{prev-a-tok-fam}";
    constexpr static std::string_view ARG_NEXT_TOK       = "{next-tok}";
    constexpr static std::string_view ARG_NEXT_TOK_FAM   = "{next-tok-fam}";
    constexpr static std::string_view ARG_NEXT_A_TOK_FAM = "{next-a-tok-fam}";

    constexpr static std::string_view ARG_BEFORE  = "{before}";
    constexpr static std::string_view ARG_BECAUSE = "{because}";

    Diagnostic() = default;
    explicit Diagnostic(const std::optional<SourceFile*>& fileOwner);
    Diagnostic(const Diagnostic&) = default;

    const std::vector<std::shared_ptr<DiagnosticElement>>& elements() const { return elements_; }
    const std::optional<SourceFile*>&                      fileOwner() const { return fileOwner_; }
    const std::vector<Argument>&                           arguments() const { return arguments_; }
    void                                                   setSilent(bool silent) { silent_ = silent; }
    bool                                                   isSilent() const { return silent_; }

    DiagnosticElement& addElement(DiagnosticId id);
    DiagnosticElement& last() const { return *elements_.back(); }
    void               addArgument(std::string_view name, std::string_view arg, bool quoted = true);

    static Diagnostic         get(DiagnosticId id, std::optional<SourceFile*> fileOwner = std::nullopt);
    static std::string_view   diagIdMessage(DiagnosticId id);
    static std::string_view   diagIdName(DiagnosticId id);
    static DiagnosticSeverity diagIdSeverity(DiagnosticId id);

    template<typename T>
    void addArgument(std::string_view name, T&& arg, bool quoted = true)
    {
        arguments_.emplace_back(Argument{name, quoted, std::forward<T>(arg)});
    }

    void report(const TaskContext& ctx) const;
};

SWC_END_NAMESPACE()
