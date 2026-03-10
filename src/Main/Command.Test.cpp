#include "pch.h"
#include "Main/Command.h"
#include "Backend/JIT/JITExecManager.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Main/CompilerInstance.h"
#include "Main/Stats.h"
#include "Wmf/SourceFile.h"
#include "Wmf/Verify.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result prepareJitFunction(TaskContext& ctx, SymbolFunction& symbol)
    {
        ctx.state().jitEmissionError = false;
        SWC_RESULT_VERIFY(symbol.emit(ctx));
        if (ctx.state().jitEmissionError)
            return Result::Error;

        symbol.jit(ctx);
        if (ctx.state().jitEmissionError || !symbol.jitEntryAddress())
            return Result::Error;

        return Result::Continue;
    }

    Result runJitFunction(TaskContext& ctx, SymbolFunction& symbol)
    {
        SWC_RESULT_VERIFY(prepareJitFunction(ctx, symbol));

        JITExecManager::Request request;
        request.function     = &symbol;
        request.nodeRef      = symbol.declNodeRef();
        request.codeRef      = symbol.codeRef();
        request.runImmediate = true;
        return ctx.compiler().jitExecMgr().submit(ctx, request);
    }

    Result runJitFunctions(TaskContext& ctx, const std::vector<SymbolFunction*>& functions)
    {
        for (SymbolFunction* symbol : functions)
        {
            if (!symbol)
                continue;
            SWC_RESULT_VERIFY(runJitFunction(ctx, *symbol));
        }

        return Result::Continue;
    }

    Result runCollectedJitTests(TaskContext& ctx)
    {
        CompilerInstance& compiler = ctx.compiler();
        SWC_RESULT_VERIFY(runJitFunctions(ctx, compiler.nativeInitFunctions()));
        SWC_RESULT_VERIFY(runJitFunctions(ctx, compiler.nativePreMainFunctions()));
        SWC_RESULT_VERIFY(runJitFunctions(ctx, compiler.nativeTestFunctions()));
        SWC_RESULT_VERIFY(runJitFunctions(ctx, compiler.nativeDropFunctions()));
        return Result::Continue;
    }

    void verifyExpectedMarkers(TaskContext& ctx)
    {
        if (Stats::get().numErrors.load(std::memory_order_relaxed) != 0)
            return;

        for (SourceFile* file : ctx.compiler().files())
        {
            if (!file)
                continue;

            const SourceView& srcView = file->ast().srcView();
            if (srcView.mustSkip())
                continue;
            file->unitTest().verifyUntouchedExpected(ctx, srcView);
        }
    }
}

namespace Command
{
    void test(CompilerInstance& compiler)
    {
        sema(compiler);
        if (Stats::get().numErrors.load(std::memory_order_relaxed) != 0)
            return;

        const bool           runArtifact = compiler.buildCfg().backendKind == Runtime::BuildCfgBackendKind::Executable;
        NativeBackendBuilder builder(compiler, runArtifact);
        if (builder.run() != Result::Continue)
            return;
        if (Stats::get().numErrors.load(std::memory_order_relaxed) != 0)
            return;

        if (runCollectedJitTests(builder.ctx()) != Result::Continue)
            return;

        verifyExpectedMarkers(builder.ctx());
    }
}

SWC_END_NAMESPACE();
