#include "pch.h"
#include "Main/Command/Command.h"
#include "Compiler/Doc/DocGenerator.h"
#include "Main/CompilerInstance.h"
#include "Main/Stats.h"
#include "Support/Report/ScopedTimedLog.h"

SWC_BEGIN_NAMESPACE();

namespace Command
{
    void doc(CompilerInstance& compiler)
    {
        const uint64_t errorsBefore = Stats::getNumErrors();
        sema(compiler);
        if (Stats::getNumErrors() != errorsBefore)
            return;

        TaskContext                   ctx(compiler);
        std::optional<ScopedTimedLog> stage;
        if (ScopedTimedLog::isOutputEnabled(ctx, ScopedTimedLog::Stage::Doc))
            stage.emplace(ctx, ScopedTimedLog::Stage::Doc);

        DocGenerator::GenerateResult result;
        const DocGenerator           generator(ctx);
        if (generator.generate(result) != Result::Continue)
        {
            if (stage)
                stage->markFailure();
            return;
        }

        if (!result.primaryOutput.empty())
            compiler.setLastArtifactLabel(Utf8(result.primaryOutput.filename()));
        if (stage)
            stage->setStat(ScopedTimedLog::formatStatCount(ctx, result.numFiles, "page"));
    }
}

SWC_END_NAMESPACE();
