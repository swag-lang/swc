#include "pch.h"
#include "Compiler/Sema/Helpers/SemaCycle.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Support/Report/Assert.h"
#include "Support/Report/DiagnosticDef.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Utf8 cyclePathString(const TaskContext& ctx, std::span<const Symbol* const> cycle)
    {
        Utf8 result;
        if (cycle.empty())
            return result;

        result += cycle.front()->name(ctx);
        for (size_t i = 1; i < cycle.size(); i++)
        {
            result += " -> ";
            result += cycle[i]->name(ctx);
        }

        result += " -> ";
        result += cycle.front()->name(ctx);
        return result;
    }

    Utf8 stalledDependencyName(const TaskContext& ctx, Sema& sema, const TaskState& state)
    {
        if (state.symbol)
            return state.symbol->name(ctx);

        if (state.idRef.isValid())
            return Utf8{sema.idMgr().get(state.idRef).name};

        return "<dependency>";
    }

    Utf8 stalledDependencyReason(const TaskState& state)
    {
        switch (state.kind)
        {
            case TaskStateKind::SemaWaitImplRegistrations:
                return "waiting for implementation registrations";
            case TaskStateKind::SemaWaitSymDeclared:
                return "waiting for declaration";
            case TaskStateKind::SemaWaitSymTyped:
                return "waiting for typing";
            case TaskStateKind::SemaWaitSymSemaCompleted:
                return "waiting for semantic analysis completion";
            case TaskStateKind::SemaWaitSymCodeGenPreSolved:
                return "waiting for code generation presolve";
            case TaskStateKind::SemaWaitSymCodeGenCompleted:
                return "waiting for code generation completion";
            case TaskStateKind::SemaWaitSymJitPrepared:
                return "waiting for JIT preparation";
            case TaskStateKind::SemaWaitSymJitPatched:
                return "waiting for JIT patching";
            case TaskStateKind::SemaWaitSymJitCompleted:
                return "waiting for JIT completion";
            case TaskStateKind::SemaWaitTypeCompleted:
                return "waiting for type completion";
            case TaskStateKind::SemaWaitTypeInfoGeneration:
                return "waiting for typeinfo generation";
            default:
                return "waiting for dependency completion";
        }
    }

    void reportStalledDependency(Sema& sema, TaskContext& ctx, const TaskState& state)
    {
#if SWC_DEV_MODE
        if (const auto* function = state.symbol ? state.symbol->safeCast<SymbolFunction>() : nullptr)
        {
            const SymbolStruct* ownerStruct = function->ownerStruct();
            const SymbolImpl*   ownerImpl   = function->declImplContext();
            std::println(stdout, "stalled-dependency-debug:");
            std::println(stdout,
                         "  blockedFn={} declared={:d} typed={:d} sema={:d} ignored={:d} genericRoot={:d} genericInstance={:d} lazy={:d} lazyRunning={:d} declNodeRef={}",
                         function->getFullScopedName(ctx).c_str(),
                         function->isDeclared(),
                         function->isTyped(),
                         function->isSemaCompleted(),
                         function->isIgnored(),
                         function->isGenericRoot(),
                         function->isGenericInstance(),
                         function->hasExtraFlag(SymbolFunctionFlagsE::LazyGenericBody),
                         function->hasExtraFlag(SymbolFunctionFlagsE::LazyGenericBodyRunning),
                         function->declNodeRef().isValid() ? function->declNodeRef().get() : 0);
            if (ownerStruct)
            {
                std::println(stdout,
                             "  ownerStruct={} declared={:d} typed={:d} sema={:d} ignored={:d} genericRoot={:d} genericInstance={:d} declNodeRef={}",
                             ownerStruct->getFullScopedName(ctx).c_str(),
                             ownerStruct->isDeclared(),
                             ownerStruct->isTyped(),
                             ownerStruct->isSemaCompleted(),
                             ownerStruct->isIgnored(),
                             ownerStruct->isGenericRoot(),
                             ownerStruct->isGenericInstance(),
                             ownerStruct->declNodeRef().isValid() ? ownerStruct->declNodeRef().get() : 0);
            }

            if (ownerImpl)
            {
                std::println(stdout,
                             "  ownerImpl={} declared={:d} typed={:d} sema={:d} ignored={:d} forStruct={:d} forInterface={:d} genericBlockRef={}",
                             static_cast<const void*>(ownerImpl),
                             ownerImpl->isDeclared(),
                             ownerImpl->isTyped(),
                             ownerImpl->isSemaCompleted(),
                             ownerImpl->isIgnored(),
                             ownerImpl->isForStruct(),
                             ownerImpl->isForInterface(),
                             ownerImpl->genericBlockRef().isValid() ? ownerImpl->genericBlockRef().get() : 0);
            }

            if (state.waiterSymbol)
            {
                std::println(stdout,
                             "  waiter={} declared={:d} typed={:d} sema={:d} ignored={:d} kind={}",
                             Utf8{state.waiterSymbol->name(ctx)}.c_str(),
                             state.waiterSymbol->isDeclared(),
                             state.waiterSymbol->isTyped(),
                             state.waiterSymbol->isSemaCompleted(),
                             state.waiterSymbol->isIgnored(),
                             static_cast<int>(state.waiterSymbol->kind()));
            }
        }
#endif
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_stalled_dependency, state.codeRef);
        diag.addArgument(Diagnostic::ARG_SYM, stalledDependencyName(ctx, sema, state));
        diag.addArgument(Diagnostic::ARG_WHAT, stalledDependencyReason(state));
        if (state.waiterSymbol)
            diag.addArgument(Diagnostic::ARG_VALUE, state.waiterSymbol->name(ctx));
        diag.report(ctx);
    }
}

void SemaCycle::addNodeIfNeeded(const Symbol* sym)
{
    if (!graph_.adj.contains(sym))
        graph_.adj[sym] = {};
}

void SemaCycle::addEdge(const Symbol* from, const Symbol* to, Job* job, const TaskState& state)
{
    addNodeIfNeeded(from);
    addNodeIfNeeded(to);

    graph_.adj[from].push_back(to);

    WaitGraph::NodeLoc& nodeLoc = graph_.edges[{from, to}];
    if (!nodeLoc.job)
    {
        nodeLoc.job     = job;
        nodeLoc.nodeRef = state.nodeRef;
        nodeLoc.codeRef = state.codeRef;
    }
}

void SemaCycle::reportCycle(const std::vector<const Symbol*>& cycle)
{
    for (const auto* sym : cycle)
        const_cast<Symbol*>(sym)->addFlag(SymbolFlagsE::Ignored);

    const Symbol* firstSym = cycle[0];
    const Symbol* nextSym  = cycle.size() > 1 ? cycle[1] : cycle[0];
    const auto    itLoc    = graph_.edges.find({firstSym, nextSym});
    if (itLoc == graph_.edges.end())
        return;

    Sema* sema = CompilerInstance::tryGetJobSema(itLoc->second.job);
    if (!sema)
        return;

    auto diag = SemaError::report(*sema, DiagnosticId::sema_err_cyclic_dependency, firstSym->codeRef());
    diag.addArgument(Diagnostic::ARG_SYM, firstSym->name(*ctx_));
    diag.addArgument(Diagnostic::ARG_WHAT, cyclePathString(*ctx_, cycle));

    for (size_t i = 0; i < cycle.size(); i++)
    {
        const Symbol* sym    = cycle[i];
        const Symbol* next   = cycle[(i + 1) % cycle.size()];
        const auto    itEdge = graph_.edges.find({sym, next});
        if (itEdge == graph_.edges.end())
            continue;
        Sema* edgeSema = CompilerInstance::tryGetJobSema(itEdge->second.job);
        if (!edgeSema)
            continue;

        diag.addNote(DiagnosticId::sema_note_cyclic_dependency_link);
        diag.last().addArgument(Diagnostic::ARG_TOK, next->name(*ctx_));
        const auto& loc = itEdge->second;
        if (loc.nodeRef.isValid() && edgeSema->ast().hasNode(loc.nodeRef))
        {
            const SourceCodeRange codeRange = edgeSema->node(loc.nodeRef).codeRangeWithChildren(edgeSema->ctx(), edgeSema->ast());
            diag.last().addSpan(codeRange, next->name(*ctx_), DiagnosticSeverity::Note);
        }
        else if (loc.codeRef.isValid())
        {
            const SourceView& srcView = edgeSema->srcView(loc.codeRef.srcViewRef);
            diag.last().addSpan(srcView.tokenCodeRange(edgeSema->ctx(), loc.codeRef.tokRef), next->name(*ctx_), DiagnosticSeverity::Note);
        }
    }

    diag.report(*ctx_);
}

void SemaCycle::findCycles(const Symbol* v, std::vector<const Symbol*>& stack, SymbolSet& visited, SymbolSet& onStack, SymbolIndexMap& stackPositions)
{
    visited.insert(v);
    onStack.insert(v);
    stackPositions.emplace(v, stack.size());
    stack.push_back(v);

    const auto it = graph_.adj.find(v);
    if (it != graph_.adj.end())
    {
        for (const auto* w : it->second)
        {
            if (onStack.contains(w))
            {
                std::vector<const Symbol*> cycle;
                const auto                 itPos = stackPositions.find(w);
                SWC_ASSERT(itPos != stackPositions.end());
                cycle.insert(cycle.end(), stack.begin() + static_cast<ptrdiff_t>(itPos->second), stack.end());
                reportCycle(cycle);
            }
            else if (!visited.contains(w))
            {
                findCycles(w, stack, visited, onStack, stackPositions);
            }
        }
    }

    stack.pop_back();
    stackPositions.erase(v);
    onStack.erase(v);
}

void SemaCycle::detectAndReportCycles()
{
    SymbolSet                  visited;
    SymbolSet                  onStack;
    std::vector<const Symbol*> stack;
    SymbolIndexMap             stackPositions;

    for (const auto& key : graph_.adj | std::views::keys)
    {
        if (!visited.contains(key))
            findCycles(key, stack, visited, onStack, stackPositions);
    }
}

void SemaCycle::check(TaskContext& ctx, JobClientId clientId)
{
    std::vector<Job*> jobs;
    ctx.global().jobMgr().waitingJobs(jobs, clientId);

    ctx_ = &ctx;
    std::unordered_set<const Symbol*> reportedSymbols;

    for (const auto job : jobs)
    {
        const auto& state = job->ctx().state();
        if (state.waiterSymbol && state.symbol)
            addEdge(state.waiterSymbol, state.symbol, job, state);
    }

    detectAndReportCycles();

    for (const auto job : jobs)
    {
        const auto& state = job->ctx().state();
        if (state.symbol && state.symbol->isIgnored())
            continue;
        if (state.waiterSymbol && state.waiterSymbol->isIgnored())
            continue;

        Sema* sema = CompilerInstance::tryGetJobSema(job);
        if (!sema)
            continue;

        if (state.kind == TaskStateKind::SemaWaitIdentifier)
        {
            auto diag = SemaError::report(*sema, DiagnosticId::sema_err_unknown_symbol, state.codeRef);
            diag.addArgument(Diagnostic::ARG_SYM, state.idRef);
            diag.report(ctx);
        }
    }

    const bool suppressStalledDependencies = Stats::hasError() || ctx.hasError();

    for (const auto job : jobs)
    {
        const auto& state = job->ctx().state();
        if (state.symbol && state.symbol->isIgnored())
            continue;
        if (state.waiterSymbol && state.waiterSymbol->isIgnored())
            continue;

        if (state.kind == TaskStateKind::SemaWaitIdentifier)
            continue;

        Sema* sema = CompilerInstance::tryGetJobSema(job);
        if (!sema)
            continue;

        if (state.waiterSymbol)
            const_cast<Symbol*>(state.waiterSymbol)->setIgnored(ctx);

        switch (state.kind)
        {
            case TaskStateKind::SemaWaitImplRegistrations:
            {
                if (suppressStalledDependencies)
                    break;
                reportStalledDependency(*sema, ctx, state);
                break;
            }

            case TaskStateKind::SemaWaitSymDeclared:
            {
                SWC_ASSERT(state.symbol);
                if (!reportedSymbols.insert(state.symbol).second)
                    break;
                if (suppressStalledDependencies)
                    break;
                reportStalledDependency(*sema, ctx, state);
                break;
            }

            case TaskStateKind::SemaWaitSymTyped:
            {
                SWC_ASSERT(state.symbol);
                if (!reportedSymbols.insert(state.symbol).second)
                    break;
                if (suppressStalledDependencies)
                    break;
                reportStalledDependency(*sema, ctx, state);
                break;
            }

            case TaskStateKind::SemaWaitSymSemaCompleted:
            {
                SWC_ASSERT(state.symbol);
                if (!reportedSymbols.insert(state.symbol).second)
                    break;
                if (suppressStalledDependencies)
                    break;
                reportStalledDependency(*sema, ctx, state);
                break;
            }

            case TaskStateKind::SemaWaitSymCodeGenPreSolved:
            {
                SWC_ASSERT(state.symbol);
                if (!reportedSymbols.insert(state.symbol).second)
                    break;
                if (suppressStalledDependencies)
                    break;
                reportStalledDependency(*sema, ctx, state);
                break;
            }

            case TaskStateKind::SemaWaitSymCodeGenCompleted:
            {
                SWC_ASSERT(state.symbol);
                if (!reportedSymbols.insert(state.symbol).second)
                    break;
                if (suppressStalledDependencies)
                    break;
                reportStalledDependency(*sema, ctx, state);
                break;
            }

            case TaskStateKind::SemaWaitSymJitPrepared:
            {
                SWC_ASSERT(state.symbol);
                if (!reportedSymbols.insert(state.symbol).second)
                    break;
                if (suppressStalledDependencies)
                    break;
                reportStalledDependency(*sema, ctx, state);
                break;
            }

            case TaskStateKind::SemaWaitSymJitPatched:
            {
                SWC_ASSERT(state.symbol);
                if (!reportedSymbols.insert(state.symbol).second)
                    break;
                if (suppressStalledDependencies)
                    break;
                reportStalledDependency(*sema, ctx, state);
                break;
            }

            case TaskStateKind::SemaWaitSymJitCompleted:
            {
                SWC_ASSERT(state.symbol);
                if (!reportedSymbols.insert(state.symbol).second)
                    break;
                if (suppressStalledDependencies)
                    break;
                reportStalledDependency(*sema, ctx, state);
                break;
            }

            case TaskStateKind::SemaWaitTypeCompleted:
            {
                if (state.symbol && !reportedSymbols.insert(state.symbol).second)
                    break;
                if (suppressStalledDependencies)
                    break;
                reportStalledDependency(*sema, ctx, state);
                break;
            }

            case TaskStateKind::SemaWaitTypeInfoGeneration:
            {
                if (state.waiterSymbol && !reportedSymbols.insert(state.waiterSymbol).second)
                    break;
                if (suppressStalledDependencies)
                    break;
                reportStalledDependency(*sema, ctx, state);
                break;
            }

            default:
                break;
        }
    }
}

SWC_END_NAMESPACE();
