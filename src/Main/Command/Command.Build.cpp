#include "pch.h"
#include "Main/Command/Command.h"
#include "Backend/JIT/JITExecManager.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Native/SymbolSort.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandRun.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Support/Report/Assert.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/Logger.h"
#include "Support/Report/ScopedTimedLog.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

namespace Command
{
    namespace
    {
        Utf8 formatCommandStageStat(const CompilerInstance& compiler, const ScopedTimedLog::StatsSnapshot& deltaSnapshot)
        {
            std::vector<Utf8> statParts;
            if (deltaSnapshot.numFiles)
                statParts.push_back(ScopedTimedLog::formatStatCount(deltaSnapshot.numFiles, "file"));
            if (!compiler.lastArtifactLabel().empty())
                statParts.push_back(Utf8{compiler.lastArtifactLabel()});
            return ScopedTimedLog::joinStatItems(statParts);
        }

        Result finishNonArtifactBackend(CompilerInstance& compiler)
        {
            TaskContext outputCtx(compiler);
            return CommandRun::afterPauses(outputCtx, [&] { return compiler.ensureCompilerMessagePass(Runtime::CompilerMsgKind::PassBeforeOutput); });
        }

        Result finishBuildBackend(CompilerInstance& compiler, const bool runArtifact)
        {
            const Runtime::BuildCfgBackendKind backendKind = effectiveBackendKind(compiler.cmdLine(), compiler.buildCfg().backendKind);
            compiler.buildCfg().backendKind                = backendKind;

            if (backendKind != Runtime::BuildCfgBackendKind::Executable)
            {
                if (!runArtifact)
                    return finishNonArtifactBackend(compiler);

                TaskContext ctx(compiler);
                Diagnostic::get(DiagnosticId::cmd_err_native_backend_kind_required).report(ctx);
                return Result::Error;
            }

            const bool runExecutable = runArtifact;

            // Workspace pipeline: build everything but the link, then hand the prepared builder back so
            // the caller can run the linker off the main thread and finish it at a later sync point.
            // The builder owns its own TaskContext, so it only needs the compiler kept alive.
            if (compiler.deferNativeLink())
            {
                auto builder = std::make_unique<NativeBackendBuilder>(compiler, runExecutable);
                if (CommandRun::afterPauses(builder->ctx(), [&] { return builder->prepareForLink(); }) != Result::Continue)
                    return Result::Error;

                compiler.setDeferredBuilder(std::move(builder));
                return Result::Continue;
            }

            TaskContext          nativeCtx(compiler);
            NativeBackendBuilder builder(compiler, runExecutable);
            return CommandRun::afterPauses(nativeCtx, [&] { return builder.run(); });
        }

        SymbolFunction* runtimeFunction(CompilerInstance& compiler, const IdentifierManager::RuntimeFunctionKind kind)
        {
            const IdentifierRef idRef = compiler.idMgr().runtimeFunction(kind);
            return compiler.runtimeFunctionSymbol(idRef);
        }

        Result runJitScriptFunction(TaskContext& ctx, const SymbolFunction& function, JITCallErrorKind* errorKind = nullptr, const uint64_t* arg0 = nullptr)
        {
            if (!function.jitEntryAddress())
                return Result::Error;

            JITExecManager::Request request;
            request.function         = &function;
            request.nodeRef          = function.declNodeRef();
            request.codeRef          = function.decl() ? function.decl()->codeRef() : SourceCodeRef::invalid();
            request.runImmediate     = true;
            request.runtimeSetupMode = JITRuntimeSetupMode::None;
            request.outCallErrorKind = errorKind;
            if (arg0)
            {
                request.arg0    = *arg0;
                request.hasArg0 = true;
            }
            return CommandRun::afterPauses(ctx, [&] { return ctx.compiler().jitExecMgr().submit(ctx, request); });
        }

        Result runJitScriptFunctions(TaskContext& ctx, bool& abandoned, std::span<SymbolFunction* const> functions, const bool finishAll = false)
        {
            bool succeeded = true;
            for (const SymbolFunction* function : functions)
            {
                if (!function)
                    continue;
                const size_t     errorsBefore = Stats::getNumErrors();
                JITCallErrorKind errorKind    = JITCallErrorKind::None;
                const Result     result       = runJitScriptFunction(ctx, *function, &errorKind);
                if (errorKind == JITCallErrorKind::HardwareException)
                {
                    abandoned = true;
                    return Result::Error;
                }

                if (result != Result::Continue || Stats::getNumErrors() != errorsBefore)
                {
                    if (!finishAll)
                        return Result::Error;
                    succeeded = false;
                }
            }

            return succeeded ? Result::Continue : Result::Error;
        }

        Result runScriptRuntimeSetup(TaskContext& ctx)
        {
            const SymbolFunction* setupFn = runtimeFunction(ctx.compiler(), IdentifierManager::RuntimeFunctionKind::SetupRuntime);
            SWC_ASSERT(setupFn != nullptr);
            if (!setupFn)
                return Result::Error;

            constexpr uint64_t flags = static_cast<uint64_t>(Runtime::RuntimeFlags::Zero);
            return runJitScriptFunction(ctx, *setupFn, nullptr, &flags);
        }

        Result finishScriptBackend(CompilerInstance& compiler)
        {
            TaskContext                   ctx(compiler);
            std::optional<ScopedTimedLog> stage;
            if (ScopedTimedLog::isOutputEnabled(ctx, ScopedTimedLog::Stage::JIT))
                stage.emplace(ctx, ScopedTimedLog::Stage::JIT);

            SWC_RESULT(CommandRun::afterPauses(ctx, [&] { return compiler.ensureCompilerMessagePass(Runtime::CompilerMsgKind::PassBeforeRunByteCode); }));

            std::vector<SymbolFunction*>         allFunctions;
            std::vector<SymbolFunction*>         initFunctions;
            std::vector<SymbolFunction*>         preMainFunctions;
            std::vector<SymbolFunction*>         mainFunctions;
            std::vector<SymbolFunction*>         dropFunctions;
            {
                NativeBackendBuilder nativeBuilder(compiler, false);
                SWC_RESULT(nativeBuilder.prepareForJit(allFunctions));
                initFunctions              = std::move(nativeBuilder.initFunctions);
                preMainFunctions           = std::move(nativeBuilder.preMainFunctions);
                mainFunctions              = std::move(nativeBuilder.mainFunctions);
                dropFunctions              = std::move(nativeBuilder.dropFunctions);
            }

            SymbolSort::sortAndUniqueByLocation(allFunctions, compiler);

            SWC_RESULT(CommandRun::afterPauses(ctx, [&] { return SymbolFunction::jitBatch(ctx, allFunctions); }));

            SWC_RESULT(runScriptRuntimeSetup(ctx));
            bool   abandoned       = false;
            Result executionResult = runJitScriptFunctions(ctx, abandoned, initFunctions);
            if (executionResult == Result::Continue)
                executionResult = runJitScriptFunctions(ctx, abandoned, preMainFunctions);
            if (executionResult == Result::Continue)
                executionResult = runJitScriptFunctions(ctx, abandoned, mainFunctions);

            // An abandoned frame may still hold resources needed by finalizers.
            if (abandoned)
                return Result::Error;

            const Result dropResult = runJitScriptFunctions(ctx, abandoned, dropFunctions, true);
            if (abandoned)
                return Result::Error;

            if (executionResult != Result::Continue || dropResult != Result::Continue)
                return Result::Error;

            if (stage)
                stage->setStat(ScopedTimedLog::formatStatCount(mainFunctions.size(), "main"));
            return Result::Continue;
        }
    }

    void build(CompilerInstance& compiler)
    {
        TaskContext ctx(compiler);

        // With detailed stages the backend reports its own 'forged' line, so keeping this
        // command-level one would print the same label twice.
        const bool detailedStages = ctx.global().logger().stagesDetailed();

        std::optional<ScopedTimedLog> stage;
        if (!detailedStages && ScopedTimedLog::isOutputEnabled(ctx, ScopedTimedLog::Stage::Build))
            stage.emplace(ctx, ScopedTimedLog::Stage::Build);
        const uint64_t errorsBefore = Stats::getNumErrors();
        {
            std::optional<Logger::ScopedStageMute> muteNestedStages;
            if (!detailedStages)
                muteNestedStages.emplace(ctx.global().logger());

            sema(compiler);
            SWC_SCHED_PHASE(ctx.global().jobMgr(), "build backend");
            if (Stats::getNumErrors() == errorsBefore && finishBuildBackend(compiler, false) != Result::Continue)
            {
                if (stage)
                    stage->markFailure();
            }
        }

        if (stage)
            stage->setStat(formatCommandStageStat(compiler, stage->delta()));
    }

    void run(CompilerInstance& compiler)
    {
        TaskContext ctx(compiler);
        const bool  detailedStages = ctx.global().logger().stagesDetailed();

        std::optional<ScopedTimedLog> stage;
        if (!detailedStages && ScopedTimedLog::isOutputEnabled(ctx, ScopedTimedLog::Stage::Run))
            stage.emplace(ctx, ScopedTimedLog::Stage::Run);
        const uint64_t errorsBefore = Stats::getNumErrors();
        {
            std::optional<Logger::ScopedStageMute> muteNestedStages;
            if (!detailedStages)
                muteNestedStages.emplace(ctx.global().logger());

            sema(compiler);
            if (Stats::getNumErrors() == errorsBefore)
            {
                // Smoke scripts use the same setup as scripts run directly, but execute in a
                // child process so the native runner can enforce their deadline.
                const bool   jitScript = compiler.cmdLine().scriptMode && compiler.cmdLine().command == CommandKind::Run;
                const Result result    = jitScript ? finishScriptBackend(compiler) : finishBuildBackend(compiler, true);
                if (result != Result::Continue)
                {
                    if (stage)
                        stage->markFailure();
                }
            }
        }

        if (stage)
            stage->setStat(formatCommandStageStat(compiler, stage->delta()));
    }
}

SWC_END_NAMESPACE();
