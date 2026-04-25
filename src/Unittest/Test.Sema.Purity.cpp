#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Main/Command/Command.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/Stats.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestSource.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct RestoreErrorCount
    {
        uint64_t saved = 0;

        ~RestoreErrorCount()
        {
            Stats::get().numErrors.store(saved, std::memory_order_relaxed);
        }
    };
}

SWC_TEST_BEGIN(SemaPurity_GlobalVariableReadIsNotConstFolded)
{
    static constexpr std::string_view SOURCE = R"(#global public

var g_Denominator: u64

func runtimeDenominator()->u64
{
    return g_Denominator
}

func divideByRuntimeDenominator(value: u64)->u64
{
    return value / runtimeDenominator()
}
)";

    const fs::path sourcePath = Unittest::makeTestSourcePath("Sema", "PurityGlobalVariableReadIsNotConstFolded");

    CommandLine cmdLine;
    cmdLine.command         = CommandKind::Sema;
    cmdLine.name            = "sema_purity_global_variable_read";
    cmdLine.moduleNamespace = "SemaPurity";
    cmdLine.silent          = true;
    cmdLine.backendOptimize = true;
    cmdLine.files.insert(sourcePath);
    CommandLineParser::refreshBuildCfg(cmdLine);

    const uint64_t    errorsBefore = Stats::getNumErrors();
    RestoreErrorCount restoreErrors{errorsBefore};
    CompilerInstance  compiler(ctx.global(), cmdLine);
    Unittest::registerTestSource(compiler, sourcePath, SOURCE);

    Command::sema(compiler);
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
