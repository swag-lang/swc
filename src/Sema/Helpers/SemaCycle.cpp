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
    enum class WaitNodeKind
    {
        Symbol,
        Type,
    };

    struct WaitNode
    {
        const void*  ptr; // Symbol* or TypeInfo*
        WaitNodeKind kind;
    };

    struct WaitNodeHash
    {
        size_t operator()(const WaitNode& n) const noexcept
        {
            return (static_cast<size_t>(n.kind) << 1) ^ std::hash<const void*>{}(n.ptr);
        }
    };

    struct WaitNodeEq
    {
        bool operator()(const WaitNode& a, const WaitNode& b) const noexcept
        {
            return a.kind == b.kind && a.ptr == b.ptr;
        }
    };

    struct WaitGraph
    {
        std::unordered_map<WaitNode, std::vector<WaitNode>, WaitNodeHash, WaitNodeEq> adj;
        std::unordered_map<WaitNode, Utf8, WaitNodeHash, WaitNodeEq>                  names;

        // For pointing diagnostics, keep a representative job + state for each node
        struct NodeLoc
        {
            SemaJob*      job     = nullptr;
            AstNodeRef    node    = AstNodeRef::invalid();
            SourceViewRef srcView = SourceViewRef::invalid();
            TokenRef      tok     = TokenRef::invalid();
        };

        std::unordered_map<WaitNode, NodeLoc, WaitNodeHash, WaitNodeEq> locs;
    };

    WaitNode makeNode(const Symbol* sym)
    {
        return {.ptr = sym, .kind = WaitNodeKind::Symbol};
    }

    WaitNode makeNode(const TypeInfo* type)
    {
        return {.ptr = type, .kind = WaitNodeKind::Type};
    }

    Utf8 getNodeName(const WaitNode& n, const TaskContext& ctx)
    {
        switch (n.kind)
        {
            case WaitNodeKind::Symbol:
                return static_cast<const Symbol*>(n.ptr)->name(ctx);
            case WaitNodeKind::Type:
                return static_cast<const TypeInfo*>(n.ptr)->toName(ctx);
            default:
                return "<unknown>";
        }
    }

    void addNodeIfNeeded(WaitGraph& g, const WaitNode& n, const TaskContext& ctx)
    {
        if (!g.names.contains(n))
            g.names[n] = getNodeName(n, ctx);
        if (!g.adj.contains(n))
            g.adj[n] = {};
    }

    void addEdge(WaitGraph& g, const WaitNode& from, const WaitNode& to, const TaskContext& ctx, SemaJob* job, const TaskState& state)
    {
        addNodeIfNeeded(g, from, ctx);
        addNodeIfNeeded(g, to, ctx);

        g.adj[from].push_back(to);

        // record a representative location for "from" if we don't have one yet
        auto& loc = g.locs[from];
        if (!loc.job)
        {
            loc.job     = job;
            loc.node    = state.nodeRef;
            loc.srcView = state.srcViewRef;
            loc.tok     = state.tokRef;
        }
    }

    void detectAndReportCycles(TaskContext& ctx, JobClientId clientId, WaitGraph& g)
    {
        using IndexMap   = std::unordered_map<WaitNode, int, WaitNodeHash, WaitNodeEq>;
        using OnStackSet = std::unordered_set<WaitNode, WaitNodeHash, WaitNodeEq>;

        IndexMap              index;
        IndexMap              lowlink;
        OnStackSet            onStack;
        std::vector<WaitNode> st;
        int                   currentIndex = 0;

        std::vector<std::vector<WaitNode>> cycles;

        std::function<void(const WaitNode&)> strongConnect = [&](const WaitNode& v) {
            index[v]   = currentIndex;
            lowlink[v] = currentIndex;
            ++currentIndex;

            st.push_back(v);
            onStack.insert(v);

            auto itAdj = g.adj.find(v);
            if (itAdj != g.adj.end())
            {
                for (const auto& w : itAdj->second)
                {
                    if (!index.contains(w))
                    {
                        strongConnect(w);
                        lowlink[v] = std::min(lowlink[v], lowlink[w]);
                    }
                    else if (onStack.contains(w))
                    {
                        lowlink[v] = std::min(lowlink[v], index[w]);
                    }
                }
            }

            if (lowlink[v] == index[v])
            {
                std::vector<WaitNode> component;
                while (true)
                {
                    WaitNode w = st.back();
                    st.pop_back();
                    onStack.erase(w);
                    component.push_back(w);
                    if (w.ptr == v.ptr && w.kind == v.kind)
                        break;
                }

                bool hasCycle = component.size() > 1;
                if (!hasCycle)
                {
                    auto itAdjV = g.adj.find(v);
                    if (itAdjV != g.adj.end())
                    {
                        for (const auto& to : itAdjV->second)
                        {
                            if (to.kind == v.kind && to.ptr == v.ptr)
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
            const WaitNode& v = key;
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
            }
            msg += " -> ";
            msg += g.names.at(cyc.front());

            // Pick a representative node for location.
            const WaitNode& rep   = cyc.front();
            auto            itLoc = g.locs.find(rep);
            SemaJob*        job   = nullptr;
            AstNodeRef      node  = AstNodeRef::invalid();

            if (itLoc != g.locs.end())
            {
                job  = itLoc->second.job;
                node = itLoc->second.node;
            }

            if (!job)
            {
                // Worst case: no specific location, just emit a global diagnostic.
                auto diag = Diagnostic::get(DiagnosticId::sema_err_cyclic_dependency);
                diag.addArgument(Diagnostic::ARG_VALUE, msg);
                diag.report(ctx);
                continue;
            }

            auto diag = SemaError::report(job->sema(), DiagnosticId::sema_err_cyclic_dependency, node);
            diag.addArgument(Diagnostic::ARG_VALUE, msg);
            diag.report(ctx);
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

        const Symbol*   waiterSym  = state.waiterSymbol;
        const TypeInfo* waiterType = state.waiterType;
        const Symbol*   waiteeSym  = nullptr;
        const TypeInfo* waiteeType = nullptr;

        switch (state.kind)
        {
            case TaskStateKind::SemaWaitSymDeclared:
            case TaskStateKind::SemaWaitSymTyped:
            case TaskStateKind::SemaWaitSymCompleted:
            case TaskStateKind::SemaWaitTypeCompleted:
                waiteeSym = state.symbol;
                break;

            default:
                break; // identifier/compiler-defined not part of symbol/type cycles
        }

        if ((waiterSym || waiterType) && (waiteeSym || waiteeType))
        {
            WaitNode from = waiterSym ? makeNode(waiterSym) : makeNode(waiterType);
            WaitNode to   = waiteeSym ? makeNode(waiteeSym) : makeNode(waiteeType);
            addEdge(graph, from, to, ctx, semaJob, state);
        }
    }

    detectAndReportCycles(ctx, clientId, graph);

    for (const auto job : jobs)
    {
        const TaskState& state = job->ctx().state();
        if (const auto semaJob = job->safeCast<SemaJob>())
        {
            switch (state.kind)
            {
                case TaskStateKind::SemaWaitIdentifier:
                {
                    auto diag = SemaError::report(semaJob->sema(), DiagnosticId::sema_err_unknown_symbol, state.srcViewRef, state.tokRef);
                    diag.addArgument(Diagnostic::ARG_SYM, state.idRef);
                    if (state.waiterSymbol)
                        diag.addArgument(Diagnostic::ARG_SYM_2, state.waiterSymbol->name(ctx));
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
                    if (state.waiterSymbol)
                        diag.addArgument(Diagnostic::ARG_SYM_2, state.waiterSymbol->name(ctx));
                    diag.report(ctx);
                    break;
                }

                case TaskStateKind::SemaWaitTypeCompleted:
                {
                    SWC_ASSERT(state.type);
                    auto diag = SemaError::report(semaJob->sema(), DiagnosticId::sema_err_wait_type_completed, state.nodeRef);
                    diag.addArgument(Diagnostic::ARG_TYPE, state.type->toName(ctx));
                    if (state.waiterType)
                        diag.addArgument(Diagnostic::ARG_TYPE_2, state.waiterType->toName(ctx));
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
