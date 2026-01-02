#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Memory/Heap.h"
#include "Report/DiagnosticDef.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Core/SemaScope.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaInfo.h"
#include "Sema/Helpers/SemaJob.h"
#include "Sema/Symbol/Symbols.h"
#include "Thread/JobManager.h"
#include "Wmf/Verify.h"

SWC_BEGIN_NAMESPACE()

Sema::Sema(TaskContext& ctx, SemaInfo& semInfo, bool declPass) :
    ctx_(&ctx),
    semaInfo_(&semInfo),
    startSymMap_(semaInfo().moduleNamespace().symMap()),
    declPass_(declPass)
{
    visit_.start(semaInfo_->ast(), semaInfo_->ast().root());
    setVisitors();
    pushFrame({});
}

Sema::Sema(TaskContext& ctx, const Sema& parent, AstNodeRef root) :
    ctx_(&ctx),
    semaInfo_(parent.semaInfo_),
    startSymMap_(parent.curScope_->symMap())

{
    visit_.start(semaInfo_->ast(), root);
    pushFrame(parent.frame());
    setVisitors();
}

Sema::~Sema() = default;

void Sema::semaInherit(AstNode& nodeDst, AstNodeRef srcRef)
{
    const AstNode& nodeSrc = node(srcRef);
    nodeDst.semaBits()     = nodeSrc.semaBits();
    nodeDst.setSemaRef(nodeSrc.semaRef());
}

ConstantManager& Sema::cstMgr()
{
    return compiler().cstMgr();
}

const ConstantManager& Sema::cstMgr() const
{
    return compiler().cstMgr();
}

TypeManager& Sema::typeMgr()
{
    return compiler().typeMgr();
}

const TypeManager& Sema::typeMgr() const
{
    return compiler().typeMgr();
}

IdentifierManager& Sema::idMgr()
{
    return compiler().idMgr();
}

const IdentifierManager& Sema::idMgr() const
{
    return compiler().idMgr();
}

SourceView& Sema::srcView(SourceViewRef srcViewRef)
{
    return compiler().srcView(srcViewRef);
}

const SourceView& Sema::srcView(SourceViewRef srcViewRef) const
{
    return compiler().srcView(srcViewRef);
}

Ast& Sema::ast()
{
    return semaInfo_->ast();
}

Utf8 Sema::fileName() const
{
    return ast().srcView().file()->path().string();
}

const Ast& Sema::ast() const
{
    return semaInfo_->ast();
}

SemaScope* Sema::pushScope(SemaScopeFlags flags)
{
    SemaScope* parent = curScope_;
    scopes_.emplace_back(std::make_unique<SemaScope>(flags, parent));
    SemaScope* scope = scopes_.back().get();
    scope->setSymMap(parent->symMap());
    curScope_ = scope;
    return scope;
}

void Sema::popScope()
{
    SWC_ASSERT(curScope_);
    curScope_ = curScope_->parent();
    scopes_.pop_back();
}

void Sema::pushFrame(const SemaFrame& frame)
{
    frame_.push_back(frame);
}

void Sema::popFrame()
{
    SWC_ASSERT(!frame_.empty());
    frame_.pop_back();
}

namespace
{
    const Symbol* guessCurrentSymbol(Sema& sema)
    {
        AstNodeRef n = sema.visit().root();
        if (sema.hasSymbol(n))
            return &sema.symbolOf(n);
        return sema.topSymMap();
    }

    const TypeInfo* guessCurrentType(Sema& sema)
    {
        AstNodeRef n = sema.visit().root();
        if (sema.hasType(n))
        {
            TypeRef tr = sema.typeRefOf(n);
            return &sema.typeMgr().get(tr);
        }
        return nullptr;
    }
}

Result Sema::waitIdentifier(IdentifierRef idRef, SourceViewRef srcViewRef, TokenRef tokRef)
{
    TaskState& wait = ctx().state();
    wait.kind       = TaskStateKind::SemaWaitIdentifier;
    wait.nodeRef    = curNodeRef();
    wait.srcViewRef = srcViewRef;
    wait.tokRef     = tokRef;
    wait.idRef      = idRef;

    // waiter info (for context; not part of cycles)
    wait.waiterSymbol = guessCurrentSymbol(*this);
    wait.waiterType   = guessCurrentType(*this);

    return Result::Pause;
}

Result Sema::waitCompilerDefined(IdentifierRef idRef, SourceViewRef srcViewRef, TokenRef tokRef)
{
    TaskState& wait = ctx().state();
    wait.kind       = TaskStateKind::SemaWaitCompilerDefined;
    wait.nodeRef    = curNodeRef();
    wait.srcViewRef = srcViewRef;
    wait.tokRef     = tokRef;
    wait.idRef      = idRef;

    wait.waiterSymbol = guessCurrentSymbol(*this);
    wait.waiterType   = guessCurrentType(*this);

    return Result::Pause;
}

Result Sema::waitDeclared(const Symbol* symbol, SourceViewRef srcViewRef, TokenRef tokRef)
{
    TaskState& wait = ctx().state();
    wait.kind       = TaskStateKind::SemaWaitSymDeclared;
    wait.nodeRef    = curNodeRef();
    wait.srcViewRef = srcViewRef;
    wait.tokRef     = tokRef;
    wait.symbol     = symbol;

    wait.waiterSymbol = guessCurrentSymbol(*this);
    wait.waiterType   = guessCurrentType(*this);

    return Result::Pause;
}

Result Sema::waitTyped(const Symbol* symbol, SourceViewRef srcViewRef, TokenRef tokRef)
{
    TaskState& wait = ctx().state();
    wait.kind       = TaskStateKind::SemaWaitSymTyped;
    wait.nodeRef    = curNodeRef();
    wait.srcViewRef = srcViewRef;
    wait.tokRef     = tokRef;
    wait.symbol     = symbol;

    wait.waiterSymbol = guessCurrentSymbol(*this);
    wait.waiterType   = guessCurrentType(*this);

    return Result::Pause;
}

Result Sema::waitCompleted(const Symbol* symbol, SourceViewRef srcViewRef, TokenRef tokRef)
{
    TaskState& wait = ctx().state();
    wait.kind       = TaskStateKind::SemaWaitSymCompleted;
    wait.nodeRef    = curNodeRef();
    wait.srcViewRef = srcViewRef;
    wait.tokRef     = tokRef;
    wait.symbol     = symbol;

    wait.waiterSymbol = guessCurrentSymbol(*this);
    wait.waiterType   = guessCurrentType(*this);

    return Result::Pause;
}

Result Sema::waitCompleted(const TypeInfo* type, AstNodeRef nodeRef)
{
    TaskState& wait = ctx().state();
    wait.kind       = TaskStateKind::SemaWaitTypeCompleted;
    wait.nodeRef    = nodeRef;

    wait.type = type;
    if (type->isStruct())
        wait.symbol = &type->structSym();
    else
        wait.symbol = nullptr;

    wait.waiterSymbol = guessCurrentSymbol(*this);
    if (wait.waiterSymbol && wait.waiterSymbol->isStruct())
        wait.waiterType = &typeMgr().get(wait.waiterSymbol->typeRef());
    else
        wait.waiterType = guessCurrentType(*this);

    return Result::Pause;
}

void Sema::setVisitors()
{
    if (declPass_)
    {
        visit_.setPreNodeVisitor([this](AstNode& node) { return preDecl(node); });
        visit_.setPreChildVisitor([this](AstNode& node, AstNodeRef& childRef) { return preDeclChild(node, childRef); });
        visit_.setPostNodeVisitor([this](AstNode& node) { return postDecl(node); });
    }
    else
    {
        visit_.setEnterNodeVisitor([this](AstNode& node) { enterNode(node); });
        visit_.setPreNodeVisitor([this](AstNode& node) { return preNode(node); });
        visit_.setPreChildVisitor([this](AstNode& node, AstNodeRef& childRef) { return preNodeChild(node, childRef); });
        visit_.setPostNodeVisitor([this](AstNode& node) { return postNode(node); });
    }
}

void Sema::enterNode(AstNode& node)
{
    const AstNodeIdInfo& info = Ast::nodeIdInfos(node.id());
    info.semaEnterNode(*this, node);
}

Result Sema::preDecl(AstNode& node)
{
    const AstNodeIdInfo& info   = Ast::nodeIdInfos(node.id());
    const Result         result = info.semaPreDecl(*this, node);
    return result;
}

Result Sema::preDeclChild(AstNode& node, AstNodeRef& childRef)
{
    const AstNodeIdInfo& info = Ast::nodeIdInfos(node.id());
    return info.semaPreDeclChild(*this, node, childRef);
}

Result Sema::postDecl(AstNode& node)
{
    const AstNodeIdInfo& info   = Ast::nodeIdInfos(node.id());
    const Result         result = info.semaPostDecl(*this, node);
    return result;
}

Result Sema::preNode(AstNode& node)
{
    const AstNodeIdInfo& info   = Ast::nodeIdInfos(node.id());
    const Result         result = info.semaPreNode(*this, node);
    return result;
}

Result Sema::postNode(AstNode& node)
{
    const AstNodeIdInfo& info   = Ast::nodeIdInfos(node.id());
    const Result         result = info.semaPostNode(*this, node);
    return result;
}

Result Sema::preNodeChild(AstNode& node, AstNodeRef& childRef)
{
    if (curScope_->hasFlag(SemaScopeFlagsE::TopLevel))
    {
        const AstNode&       child = ast().node(childRef);
        const AstNodeIdInfo& info  = Ast::nodeIdInfos(child.id());
        if (info.hasFlag(AstNodeIdFlagsE::SemaJob))
        {
            const auto job = heapNew<SemaJob>(ctx(), *this, childRef);
            compiler().global().jobMgr().enqueue(*job, JobPriority::Normal, compiler().jobClientId());
            return Result::SkipChildren;
        }
    }

    const AstNodeIdInfo& info = Ast::nodeIdInfos(node.id());
    return info.semaPreNodeChild(*this, node, childRef);
}

namespace
{
    bool resolveCompilerDefined(const TaskContext& ctx, JobClientId clientId)
    {
        std::vector<Job*> jobs;
        ctx.global().jobMgr().waitingJobs(jobs, clientId);

        bool doneSomething = false;
        for (const auto job : jobs)
        {
            const TaskState& state = job->ctx().state();
            if (state.kind == TaskStateKind::SemaWaitCompilerDefined)
            {
                // @CompilerNotDefined
                const auto semaJob = job->cast<SemaJob>();
                semaJob->sema().setConstant(state.nodeRef, semaJob->sema().cstMgr().cstFalse());
                doneSomething = true;
            }
        }

        return doneSomething;
    }

    enum class WaitNodeKind : uint8_t
    {
        Symbol,
        Type,
    };

    struct WaitNode
    {
        WaitNodeKind kind;
        const void*  ptr; // Symbol* or TypeInfo*
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
        return {WaitNodeKind::Symbol, sym};
    }

    WaitNode makeNode(const TypeInfo* type)
    {
        return {WaitNodeKind::Type, type};
    }

    Utf8 getNodeName(const WaitNode& n, TaskContext& ctx)
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

    void addNodeIfNeeded(WaitGraph& g, const WaitNode& n, TaskContext& ctx)
    {
        if (!g.names.count(n))
            g.names[n] = getNodeName(n, ctx);
        if (!g.adj.count(n))
            g.adj[n] = {};
    }

    void addEdge(WaitGraph& g, const WaitNode& from, const WaitNode& to, TaskContext& ctx, SemaJob* job, const TaskState& state)
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
                    if (!index.count(w))
                    {
                        strongConnect(w);
                        lowlink[v] = std::min(lowlink[v], lowlink[w]);
                    }
                    else if (onStack.count(w))
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

        for (const auto& kv : g.adj)
        {
            const WaitNode& v = kv.first;
            if (!index.count(v))
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
            const WaitNode& rep     = cyc.front();
            auto            itLoc   = g.locs.find(rep);
            SemaJob*        job     = nullptr;
            AstNodeRef      node    = AstNodeRef::invalid();
            SourceViewRef   srcView = SourceViewRef::invalid();
            TokenRef        tok     = TokenRef::invalid();

            if (itLoc != g.locs.end())
            {
                job     = itLoc->second.job;
                node    = itLoc->second.node;
                srcView = itLoc->second.srcView;
                tok     = itLoc->second.tok;
            }

            if (!job)
            {
                // Worst case: no specific location, just emit a global diagnostic.
                // You need a DiagnosticId like sema_err_cyclic_dependency with a string arg.
                auto diag = Diagnostic::get(DiagnosticId::sema_err_cyclic_dependency);
                diag.addArgument(Diagnostic::ARG_VALUE, msg);
                diag.report(ctx);
                continue;
            }

            // Overload choice depends on your SemaError::report; here we assume
            // a node-based overload. Adjust if needed.
            auto diag = SemaError::report(job->sema(), DiagnosticId::sema_err_cyclic_dependency, node);
            diag.addArgument(Diagnostic::ARG_VALUE, msg);
            diag.report(ctx);
        }
    }

    void postPass(TaskContext& ctx, JobClientId clientId)
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

                    // case TaskStateKind::SemaWaitTypeCompleted:
                    //     waiteeType = state.type;
                    //     break;

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

        for (const auto& f : ctx.compiler().files())
        {
            const SourceView& srcView = f->ast().srcView();
            if (srcView.mustSkip())
                continue;
            f->unitTest().verifyUntouchedExpected(ctx, srcView);
        }
    }

}

JobResult Sema::exec()
{
    if (!curScope_)
    {
        scopes_.emplace_back(std::make_unique<SemaScope>(SemaScopeFlagsE::TopLevel, nullptr));
        curScope_ = scopes_.back().get();
        curScope_->setSymMap(startSymMap_);
    }

    ctx().state().reset();

    JobResult jobResult;
    while (true)
    {
        const AstVisitResult result = visit_.step(ctx());
        if (result == AstVisitResult::Pause)
        {
            jobResult = JobResult::Sleep;
            break;
        }

        if (result == AstVisitResult::Stop)
        {
            jobResult = JobResult::Done;
            break;
        }
    }

    if (jobResult == JobResult::Done)
        scopes_.clear();
    return jobResult;
}

void Sema::waitDone(TaskContext& ctx, JobClientId clientId)
{
    auto&             jobMgr   = ctx.global().jobMgr();
    CompilerInstance& compiler = ctx.compiler();

    while (true)
    {
        jobMgr.waitAll(clientId);

        if (compiler.changed())
        {
            compiler.clearChanged();
            jobMgr.wakeAll(clientId);
            continue;
        }

        if (resolveCompilerDefined(ctx, clientId))
        {
            jobMgr.wakeAll(clientId);
            continue;
        }

        break;
    }

    postPass(ctx, clientId);
}

SWC_END_NAMESPACE()
