#include "pch.h"
#include "Main/Command/Command.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Parser/ParserJob.h"
#include "Compiler/SourceFile.h"
#include "Compiler/Verify.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Support/Report/ScopedTimedLog.h"
#include "Support/Thread/Job.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

namespace Command
{
    void syntax(CompilerInstance& compiler)
    {
        TaskContext                   ctx(compiler);
        std::optional<ScopedTimedLog> stage;
        if (ScopedTimedLog::isOutputEnabled(ctx, ScopedTimedLog::Stage::Syntax))
            stage.emplace(ctx, ScopedTimedLog::Stage::Syntax);

        if (compiler.collectFiles(ctx) == Result::Error)
            return;

        parseSourceFiles(ctx, compiler.files());

        if (stage)
            stage->setStat(ScopedTimedLog::formatStatCount(ctx, compiler.files().size(), "file"));

        if (!Stats::hasError())
        {
            for (SourceFile* f : compiler.files())
            {
                if (!f->ast().hasSourceView())
                    continue;

                const SourceView& srcView = f->ast().srcView();
                if (srcView.mustSkip())
                    continue;
                f->unitTest().verifyUntouchedExpected(ctx, srcView);
            }
        }
    }
}

SWC_END_NAMESPACE();
