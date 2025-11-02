#pragma once
#include "Report/DiagnosticElement.h"

SWC_BEGIN_NAMESPACE()

enum class LogColor;

class Context;
enum class DiagnosticId;
enum class TokenId : uint16_t;

enum class DiagnosticSeverity
{
    Error,
    Warning,
    Note,
    Help,
};

enum class DiagnosticId
{
    None = 0,
#define SWC_DIAG_DEF(id) id,
#include "Report/Diagnostic_Errors_.def"

#include "Report/Diagnostic_Notes_.def"

#undef SWC_DIAG_DEF
    Count,
};

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
    const Context*                                  context_   = nullptr;

public:
    constexpr static std::string_view ARG_PATH    = "{path}";
    constexpr static std::string_view ARG_ARG     = "{arg}";
    constexpr static std::string_view ARG_COMMAND = "{command}";
    constexpr static std::string_view ARG_VALUE   = "{value}";
    constexpr static std::string_view ARG_VALUES  = "{values}";
    constexpr static std::string_view ARG_LONG    = "{long}";
    constexpr static std::string_view ARG_SHORT   = "{short}";

    constexpr static std::string_view ARG_TOK          = "{tok}";
    constexpr static std::string_view ARG_TOK_FAM      = "{tok-fam}";
    constexpr static std::string_view ARG_A_TOK_FAM    = "{a-tok-fam}";
    constexpr static std::string_view ARG_EXPECT       = "{expect-tok}";
    constexpr static std::string_view ARG_EXPECT_FAM   = "{expect-tok-fam}";
    constexpr static std::string_view ARG_A_EXPECT_FAM = "{expect-a-tok-fam}";

    constexpr static std::string_view ARG_AFTER   = "{after}";
    constexpr static std::string_view ARG_BEFORE  = "{before}";
    constexpr static std::string_view ARG_BECAUSE = "{because}";

    Diagnostic() = default;
    explicit Diagnostic(const Context& context, const std::optional<SourceFile*>& fileOwner = std::nullopt);
    Diagnostic(const Diagnostic&) = default;

    const std::vector<std::shared_ptr<DiagnosticElement>>& elements() const { return elements_; }
    const std::optional<SourceFile*>&                      fileOwner() const { return fileOwner_; }
    const std::vector<Argument>&                           arguments() const { return arguments_; }

    DiagnosticElement& addElement(DiagnosticId id);
    DiagnosticElement& last() const { return *elements_.back(); }
    void               addArgument(std::string_view name, std::string_view arg, bool quoted = true);

    static Diagnostic         get(const Context& ctx, DiagnosticId id, std::optional<SourceFile*> fileOwner = std::nullopt);
    static std::string_view   diagIdMessage(DiagnosticId id);
    static std::string_view   diagIdName(DiagnosticId id);
    static DiagnosticSeverity diagIdSeverity(DiagnosticId id);

    template<typename T>
    void addArgument(std::string_view name, T&& arg, bool quoted = true)
    {
        arguments_.emplace_back(Argument{name, quoted, std::forward<T>(arg)});
    }

    void report(const Context& ctx) const;
};

SWC_END_NAMESPACE()
