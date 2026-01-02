#include "pch.h"
#include "Sema/Helpers/SemaCycle.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Report/DiagnosticDef.h"
#include "Sema/Core/Sema.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaJob.h"
#include "Thread/JobManager.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    struct WaitGraph
    {
        std::unordered_map<const Symbol*, std::vector<const Symbol*>> adj;
        std::unordered_map<const Symbol*, Utf8>                       names;

        // For pointing diagnostics, keep a representative job + state for each node
        struct NodeLoc
        {
            SemaJob*      job     = nullptr;
            AstNodeRef    nodeRef = AstNodeRef::invalid();
            SourceViewRef srcView = SourceViewRef::invalid();
            TokenRef      tok     = TokenRef::invalid();
        };

        std::unordered_map<const Symbol*, NodeLoc> locs;
    };

    void addNodeIfNeeded(WaitGraph& g, const Symbol* sym, const TaskContext& ctx)
    {
        if (!g.names.contains(sym))
            g.names[sym] = sym->name(ctx);
        if (!g.adj.contains(sym))
            g.adj[sym] = {};
    }

    void addEdge(WaitGraph& g, const Symbol* from, const Symbol* to, const TaskContext& ctx, SemaJob* job, const TaskState& state)
    {
        addNodeIfNeeded(g, from, ctx);
        addNodeIfNeeded(g, to, ctx);

        g.adj[from].push_back(to);

        // record a representative location for "from" if we don't have one yet
        auto& loc = g.locs[from];
        if (!loc.job)
        {
            loc.job     = job;
            loc.nodeRef = state.nodeRef;
            loc.srcView = state.srcViewRef;
            loc.tok     = state.tokRef;
        }
    }

    void detectAndReportCycles(TaskContext& ctx, JobClientId clientId, WaitGraph& g)
    {
        using IndexMap   = std::unordered_map<const Symbol*, int>;
        using OnStackSet = std::unordered_set<const Symbol*>;

        IndexMap                   index;
        IndexMap                   lowLink;
        OnStackSet                 onStack;
        std::vector<const Symbol*> st;
        int                        currentIndex = 0;

        std::vector<std::vector<const Symbol*>> cycles;

        std::function<void(const Symbol*)> strongConnect = [&](const Symbol* v) {
            index[v]   = currentIndex;
            lowLink[v] = currentIndex;
            ++currentIndex;

            st.push_back(v);
            onStack.insert(v);

            auto itAdj = g.adj.find(v);
            if (itAdj != g.adj.end())
            {
                for (const auto w : itAdj->second)
                {
                    if (!index.contains(w))
                    {
                        strongConnect(w);
                        lowLink[v] = std::min(lowLink[v], lowLink[w]);
                    }
                    else if (onStack.contains(w))
                    {
                        lowLink[v] = std::min(lowLink[v], index[w]);
                    }
                }
            }

            if (lowLink[v] == index[v])
            {
                std::vector<const Symbol*> component;
                while (true)
                {
                    const Symbol* w = st.back();
                    st.pop_back();
                    onStack.erase(w);
                    component.push_back(w);
                    if (w == v)
                        break;
                }

                bool hasCycle = component.size() > 1;
                if (!hasCycle)
                {
                    auto itAdjV = g.adj.find(v);
                    if (itAdjV != g.adj.end())
                    {
                        for (const auto to : itAdjV->second)
                        {
                            if (to == v)
                            {
                                hasCycle = true;
                                break;
                            }
                        }
                    }
                }

                if (hasCycle)
                    cycles.push_back(std::move(component));
            }
        };

        for (const auto& key : g.adj | std::views::keys)
        {
            const Symbol* v = key;
            if (!index.contains(v))
                strongConnect(v);
        }

        // Emit one diagnostic per strongly connected component that is actually a cycle.
        for (const auto& cyc : cycles)
        {
            if (cyc.empty())
                continue;

            // Build "A -> B -> C -> A"
            Utf8 msg;
            for (size_t i = 0; i < cyc.size(); ++i)
            {
                if (i)
                    msg += " -> ";
                msg += g.names.at(cyc[i]);
                const_cast<Symbol*>(cyc[i])->addFlag(SymbolFlagsE::Ignored);
            }

            msg += " -> ";
            msg += g.names.at(cyc.front());

            // Pick a representative node for a location.
            const Symbol* rep   = cyc.front();
            auto          itLoc = g.locs.find(rep);
            if (itLoc != g.locs.end())
            {
                SemaJob*   job     = itLoc->second.job;
                AstNodeRef nodeRef = itLoc->second.nodeRef;
                auto       diag    = SemaError::report(job->sema(), DiagnosticId::sema_err_cyclic_dependency, nodeRef);
                diag.addArgument(Diagnostic::ARG_VALUE, msg);
                diag.report(ctx);
            }
        }
    }
}

void SemaCycle::check(TaskContext& ctx, JobClientId clientId)
{
    std::vector<Job*> jobs;
    ctx.global().jobMgr().waitingJobs(jobs, clientId);

    WaitGraph graph;
    for (const auto job : jobs)
    {
        const TaskState& state   = job->ctx().state();
        auto*            semaJob = job->safeCast<SemaJob>();
        if (!semaJob)
            continue;
        if (state.waiterSymbol && state.symbol)
            addEdge(graph, state.waiterSymbol, state.symbol, ctx, semaJob, state);
    }

    detectAndReportCycles(ctx, clientId, graph);

    for (const auto job : jobs)
    {
        const TaskState& state = job->ctx().state();
        if (state.symbol && state.symbol->isIgnored())
            continue;

        if (const auto semaJob = job->safeCast<SemaJob>())
        {
            switch (state.kind)
            {
                case TaskStateKind::SemaWaitIdentifier:
                {
                    auto diag = SemaError::report(semaJob->sema(), DiagnosticId::sema_err_unknown_symbol, state.srcViewRef, state.tokRef);
                    diag.addArgument(Diagnostic::ARG_SYM, state.idRef);
                    diag.report(ctx);
                    break;
                }

                case TaskStateKind::SemaWaitSymDeclared:
                case TaskStateKind::SemaWaitSymTyped:
                case TaskStateKind::SemaWaitSymCompleted:
                {
                    SWC_ASSERT(state.symbol);
                    auto diag = SemaError::report(semaJob->sema(), DiagnosticId::sema_err_wait_sym_completed, state.srcViewRef, state.tokRef);
                    diag.addArgument(Diagnostic::ARG_SYM, state.symbol->name(ctx));
                    diag.report(ctx);
                    break;
                }

                case TaskStateKind::SemaWaitTypeCompleted:
                {
                    SWC_ASSERT(state.symbol);
                    auto diag = SemaError::report(semaJob->sema(), DiagnosticId::sema_err_wait_sym_completed, state.nodeRef);
                    diag.addArgument(Diagnostic::ARG_SYM, state.symbol->name(ctx));
                    diag.report(ctx);
                    break;
                }

                default:
                    SWC_UNREACHABLE();
            }
        }
    }
}

SWC_END_NAMESPACE()
