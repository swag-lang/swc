#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Support/Report/Diagnostic.h"
#include "Support/Report/WarningPolicy.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    // Two warnings the policy tests can name without depending on what either one says.
    constexpr DiagnosticId K_WARN_A = DiagnosticId::sema_warn_unreachable_code;
    constexpr DiagnosticId K_WARN_B = DiagnosticId::sema_warn_compiler_warning;
}

SWC_TEST_BEGIN(WarningPolicy_ReadsWarningIdentifiers)
{
    if (!WarningPolicy::isWarningId(K_WARN_A) || !WarningPolicy::isWarningId(K_WARN_B))
        return Result::Error;
    if (WarningPolicy::isWarningId(DiagnosticId::sema_err_expr_not_const))
        return Result::Error;
    if (WarningPolicy::isWarningId(DiagnosticId::None))
        return Result::Error;

    if (WarningPolicy::findId(Diagnostic::diagIdName(K_WARN_A)) != K_WARN_A)
        return Result::Error;
    if (WarningPolicy::findId("sema_err_expr_not_const") != DiagnosticId::None)
        return Result::Error;
    if (WarningPolicy::findId("nope") != DiagnosticId::None)
        return Result::Error;

    // 'all' is offered as a name so a typo can be corrected towards it too.
    const std::vector<Utf8> names = WarningPolicy::allIdNames();
    if (std::ranges::find(names, Utf8{WarningPolicy::ALL}) == names.end())
        return Result::Error;
    if (std::ranges::find(names, Utf8{Diagnostic::diagIdName(K_WARN_B)}) == names.end())
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(WarningPolicy_ParsesLists)
{
    WarningPolicy policy;
    if (!policy.empty())
        return Result::Error;

    const Utf8 both = Utf8{Diagnostic::diagIdName(K_WARN_A)} + " | " + Utf8{Diagnostic::diagIdName(K_WARN_B)};
    if (policy.addList(both, WarningLevel::Error).has_value())
        return Result::Error;
    if (policy.levelOf(K_WARN_A) != WarningLevel::Error || policy.levelOf(K_WARN_B) != WarningLevel::Error)
        return Result::Error;
    if (policy.blanketLevel().has_value())
        return Result::Error;

    // The last decision on a name wins, and 'all' only sets the blanket level.
    if (policy.addList(Utf8{Diagnostic::diagIdName(K_WARN_A)} + ",all", WarningLevel::Disable).has_value())
        return Result::Error;
    if (policy.levelOf(K_WARN_A) != WarningLevel::Disable || policy.levelOf(K_WARN_B) != WarningLevel::Error)
        return Result::Error;
    if (policy.blanketLevel() != WarningLevel::Disable)
        return Result::Error;

    const std::optional<Utf8> unknown = policy.addList("nope", WarningLevel::Error);
    if (!unknown.has_value() || unknown.value() != "nope")
        return Result::Error;

    policy.reset();
    if (!policy.empty() || policy.blanketLevel().has_value() || policy.levelOf(K_WARN_A).has_value())
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(WarningPolicy_ResolvesLayerPrecedence)
{
    WarningLevelQuery query;
    query.id = K_WARN_A;

    // Nothing said: a warning stays a warning.
    if (resolveWarningLevel(query) != WarningLevel::Warning)
        return Result::Error;

    WarningPolicy cmdLine;
    WarningPolicy buildCfg;
    query.cmdLine  = &cmdLine;
    query.buildCfg = &buildCfg;

    // At equal reach the innermost layer wins: source, then build config, then command line.
    cmdLine.setBlanketLevel(WarningLevel::Error);
    if (resolveWarningLevel(query) != WarningLevel::Error)
        return Result::Error;

    buildCfg.setBlanketLevel(WarningLevel::Disable);
    if (resolveWarningLevel(query) != WarningLevel::Disable)
        return Result::Error;

    query.sourceBlanketLevel = WarningLevel::Warning;
    if (resolveWarningLevel(query) != WarningLevel::Warning)
        return Result::Error;

    // A decision that names the warning outranks every blanket decision, whichever layer
    // it comes from, so a command line '--warn-as-error <name>' survives 'cfg.warnings.disabled = "all"'.
    cmdLine.setLevel(K_WARN_A, WarningLevel::Error);
    if (resolveWarningLevel(query) != WarningLevel::Error)
        return Result::Error;

    // ... and among named decisions, the innermost layer still wins.
    buildCfg.setLevel(K_WARN_A, WarningLevel::Warning);
    if (resolveWarningLevel(query) != WarningLevel::Warning)
        return Result::Error;

    query.sourceLevel = WarningLevel::Disable;
    if (resolveWarningLevel(query) != WarningLevel::Disable)
        return Result::Error;

    // Another warning is untouched by decisions that named this one.
    query.id                 = K_WARN_B;
    query.sourceBlanketLevel = std::nullopt;
    query.sourceLevel        = std::nullopt;
    if (resolveWarningLevel(query) != WarningLevel::Disable)
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
