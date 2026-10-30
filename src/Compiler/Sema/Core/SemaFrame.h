#pragma once
#include "Compiler/Parser/Ast/AstNode.h"
#include "Compiler/Sema/Core/AttributeList.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Support/Core/Flags.h"
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

class SymbolEnum;
class SemaScope;
class Ast;
struct SemaInlinePayload;

struct SemaCompilerIf
{
    std::vector<Symbol*> symbols;
    SemaCompilerIf*      parent = nullptr;
    std::mutex           symbolsMutex;

    // Static-control payloads are shared by independent SemaJobs. Lock writes
    // while declarations register themselves along the chain. Reads occur only
    // after all branch children complete and need no lock.
    void addSymbolToChain(Symbol* sym)
    {
        for (auto it = this; it; it = it->parent)
        {
            const std::scoped_lock lock(it->symbolsMutex);
            it->symbols.push_back(sym);
        }
    }
};

struct SemaNamedScope
{
    IdentifierRef   idRef    = IdentifierRef::invalid();
    AstNodeRef      scopeRef = AstNodeRef::invalid();
    SemaNamedScope* parent   = nullptr;
};

struct SemaLookupScopeOverrideNodes
{
    const Ast*                     ast = nullptr;
    std::unordered_set<AstNodeRef> nodeRefs;
};

// Track the storage iterated by an enclosing loop. Structural mutation can
// invalidate its count snapshot or reallocate the buffer aliased by &it.
// Frame inheritance carries the borrow through inline/macro expansion and
// restores the previous set when the loop frame pops, including on errors.
struct SemaIterationBorrow
{
    const SymbolVariable* root      = nullptr;
    AstNodeRef            sourceRef = AstNodeRef::invalid();

    // A mutation followed by a loop exit is safe from later iterations. Keep
    // the body so analysis can prove the count snapshot is never reused.
    AstNodeRef bodyRef = AstNodeRef::invalid();
};

enum class SemaFrameContextFlagsE
{
    Zero              = 0,
    RunExpr           = 1 << 0,
    RequireConstExpr  = 1 << 1,
    CompilerEval      = 1 << 2,
    GeneratedTopLevel = 1 << 3,
};
using SemaFrameContextFlags = EnumFlags<SemaFrameContextFlagsE>;

// Flow facts share storage, scoping, and kill rules. New kinds also need
// recognition in SemaHelpers::collectNarrowGuards and a consuming query.
enum class SemaNarrowFactKind : uint8_t
{
    NonNull, // the path cannot be null: consumed by the use-site nullability rules
    NonZero, // the path cannot be zero
    Case,    // the path is a tagged union whose tag is one of 'cases': consumed by payload access
};

// An access path is a root variable followed by field symbols (p or me.lastBucket).
// holds proves the path here; a kill invalidates every kind on the path and its
// descendants after assignment or address-of. The kind of a kill is irrelevant.
struct SemaNarrowFact
{
    SmallVector4<const Symbol*>  path;
    std::span<const ConstantRef> cases; // Case only: arena-owned, never mutated once published
    SemaNarrowFactKind           kind  = SemaNarrowFactKind::NonNull;
    bool                         holds = true;
};

class SemaFrame
{
public:
    // A 'scope' is deliberately absent: it is reachable by 'break to <name>' only, never by a
    // bare 'break' or by 'continue', so it never becomes the current break or continue context.
    enum class BreakContextKind : uint8_t
    {
        None,
        Loop,
        Switch,
    };

    enum class ErrorContextMode : uint8_t
    {
        None,
        Try,
        Catch,
        Expect,
    };

    struct BreakContext
    {
        AstNodeRef       nodeRef = AstNodeRef::invalid();
        BreakContextKind kind    = BreakContextKind::None;
    };

    std::span<const IdentifierRef> nsPath() const { return nsPath_; }
    void                           pushNs(IdentifierRef id) { nsPath_.push_back(id); }
    void                           popNs() { nsPath_.pop_back(); }

    SymbolAccess currentAccess() const { return access_; }
    void         setCurrentAccess(SymbolAccess access) { access_ = access; }

    // An access modifier applies only to members of its owning aggregate. Nested
    // aggregates default to internal; anonymous aggregates cannot be annotated
    // and remain accessible through the value that holds them.
    MemberAccessSpec memberAccessFor(const SymbolMap* symMap) const;
    void             setCurrentMemberAccess(MemberAccessSpec access, const SymbolMap* symMap)
    {
        memberAccess_    = access;
        memberAccessMap_ = symMap;
    }

    bool globalCompilerIfEnabled() const { return globalCompilerIfEnabled_; }
    void setGlobalCompilerIfEnabled(bool value) { globalCompilerIfEnabled_ = value; }

    AttributeList&       currentAttributes() { return attributes_; }
    const AttributeList& currentAttributes() const { return attributes_; }

    SemaCompilerIf* currentCompilerIf() const { return compilerIf_; }
    void            setCurrentCompilerIf(SemaCompilerIf* ifc) { compilerIf_ = ifc; }

    const SymbolImpl* currentImpl() const { return impl_; }
    void              setCurrentImpl(const SymbolImpl* impl) { impl_ = impl; }

    const SymbolInterface* currentInterface() const { return interface_; }
    void                   setCurrentInterface(const SymbolInterface* itf) { interface_ = itf; }

    SymbolFunction* currentFunction() const { return function_; }
    void            setCurrentFunction(SymbolFunction* func) { function_ = func; }
    SymbolFunction* enclosingFunction() const { return enclosingFunction_; }
    void            setEnclosingFunction(SymbolFunction* func) { enclosingFunction_ = func; }

    SemaNamedScope* currentNamedScope() const { return namedScope_; }
    void            setCurrentNamedScope(SemaNamedScope* scope) { namedScope_ = scope; }

    SemaFrameContextFlags contextFlags() const { return contextFlags_; }
    bool                  hasContextFlag(SemaFrameContextFlagsE flag) const { return contextFlags_.has(flag); }
    void                  addContextFlag(SemaFrameContextFlagsE flag) { contextFlags_.add(flag); }
    void                  removeContextFlag(SemaFrameContextFlagsE flag) { contextFlags_.remove(flag); }

    AstNodeRef syntaxScopeNodeRef() const { return syntaxScopeNodeRef_; }
    void       setSyntaxScopeNodeRef(AstNodeRef nodeRef) { syntaxScopeNodeRef_ = nodeRef; }

    SemaInlinePayload*       currentInlinePayload() { return inlinePayload_; }
    const SemaInlinePayload* currentInlinePayload() const { return inlinePayload_; }
    void                     setCurrentInlinePayload(SemaInlinePayload* payload) { inlinePayload_ = payload; }
    AstNodeRef               inlineContextRootRef() const { return inlineContextRootRef_; }
    void                     setInlineContextRootRef(AstNodeRef nodeRef) { inlineContextRootRef_ = nodeRef; }

    SemaScope* lookupScope() const { return lookupScope_; }
    void       setLookupScope(SemaScope* scope) { lookupScope_ = scope; }

    const SemaLookupScopeOverrideNodes* lookupScopeOverrideNodes() const { return lookupScopeOverrideNodes_; }
    void                                setLookupScopeOverrideNodes(const SemaLookupScopeOverrideNodes* nodes) { lookupScopeOverrideNodes_ = nodes; }

    SemaScope* upLookupScope() const { return upLookupScope_; }
    void       setUpLookupScope(SemaScope* scope) { upLookupScope_ = scope; }

    bool ignoreRuntimeAccess() const { return ignoreRuntimeAccess_; }
    void setIgnoreRuntimeAccess(bool value) { ignoreRuntimeAccess_ = value; }
    bool ignoreRedirectedLookupSymMaps() const { return ignoreRedirectedLookupSymMaps_; }
    void setIgnoreRedirectedLookupSymMaps(bool value) { ignoreRedirectedLookupSymMaps_ = value; }

    const BreakContext& currentBreakContext() const { return breakable_; }
    void                setCurrentBreakContent(AstNodeRef nodeRef, BreakContextKind kind);
    BreakContextKind    currentBreakableKind() const { return breakable_.kind; }
    const BreakContext& currentContinueContext() const { return continuable_; }
    BreakContextKind    currentContinuableKind() const { return continuable_.kind; }

    // 'scope' is not a bare break/continue target. Keep the innermost scope for
    // diagnostics when no enclosing loop provides the intended target.
    AstNodeRef currentScopeStmt() const { return scopeStmt_; }
    void       setCurrentScopeStmt(AstNodeRef nodeRef) { scopeStmt_ = nodeRef; }

    AstNodeRef       currentErrorScope() const { return currentErrorScope_; }
    ErrorContextMode currentErrorContextMode() const { return currentErrorContextMode_; }
    void             setCurrentErrorContext(AstNodeRef nodeRef, ErrorContextMode mode)
    {
        currentErrorScope_       = nodeRef;
        currentErrorContextMode_ = mode;
    }

    AstNodeRef currentSwitch() const { return currentSwitch_; }
    void       setCurrentSwitch(AstNodeRef nodeRef) { currentSwitch_ = nodeRef; }
    AstNodeRef currentSwitchCase() const { return currentSwitchCase_; }
    void       setCurrentSwitchCase(AstNodeRef nodeRef) { currentSwitchCase_ = nodeRef; }

    AstNodeRef      currentRuntimeStorageNodeRef() const { return runtimeStorageNodeRef_; }
    SymbolVariable* currentRuntimeStorageSym() const { return runtimeStorageSym_; }
    void            setCurrentRuntimeStorage(AstNodeRef nodeRef, SymbolVariable* sym)
    {
        runtimeStorageNodeRef_ = nodeRef;
        runtimeStorageSym_     = sym;
    }

    std::span<const SemaIterationBorrow> iterationBorrows() const { return iterationBorrows_.span(); }
    void                                 pushIterationBorrow(const SemaIterationBorrow& borrow) { iterationBorrows_.push_back(borrow); }

    // Contextual types guide expression analysis. The first scopeBindingCount_
    // belong to an enclosing statement (such as an enum switch); remaining types
    // apply to one expression and are cleared at the next statement.
    std::span<const TypeRef> bindingTypes() const { return bindingTypes_.span(); }
    bool                     hasExpressionBindingTypes() const { return bindingTypes_.size() > scopeBindingCount_; }
    void                     pushBindingType(TypeRef type);
    void                     pushScopeBindingType(TypeRef type);
    void                     popBindingType();
    void                     clearBindingTypes();

    std::span<SymbolVariable* const> bindingVars() const { return bindingVars_.span(); }
    void                             pushBindingVar(SymbolVariable* sym);
    void                             popBindingVar();

    void hideLookupSymbol(const Symbol* sym);
    bool isLookupSymbolHidden(const Symbol* sym) const;

    // Operand-only frames scope binding types and name lookup (initializers or
    // assignment rhs), not flow proofs. Facts recorded through such a frame
    // belong to the statement's own frame beneath it.
    bool bindingScoped() const { return bindingScoped_; }
    void setBindingScoped() { bindingScoped_ = true; }
    void clearBindingScoped() { bindingScoped_ = false; }

    // Deferred code runs at scope exit. Its flow kills stop at this frame so they
    // cannot invalidate proofs used by code between the defer and that exit.
    bool deferBody() const { return deferBody_; }
    void setDeferBody() { deferBody_ = true; }

    // Remember the function/inline expansion owning this defer. A return from a
    // nested lambda or inlined callee stays inside the deferred body. Deferred fail
    // has its own meaning: fail the scope or replace its error.
    bool returnLeavesDefer() const { return deferBody_ && function_ == deferFunction_ && inlinePayload_ == deferInlinePayload_; }
    void setDeferOwner()
    {
        deferFunction_      = function_;
        deferInlinePayload_ = inlinePayload_;
    }

    void addNarrowFact(std::span<const Symbol* const> path, SemaNarrowFactKind kind);
    void addNarrowCaseFact(std::span<const Symbol* const> path, std::span<const ConstantRef> cases);
    void addNarrowKill(std::span<const Symbol* const> path);

    // The newest live Case fact on exactly this path, or null once a kill reaches it.
    static const SemaNarrowFact* findNarrowCases(std::span<const SemaNarrowFact> facts, std::span<const Symbol* const> path);
    // Whether the path is proven to hold one of 'allowed'.
    bool queryNarrowCases(std::span<const Symbol* const> path, std::span<const ConstantRef> allowed) const;
    bool queryNarrowFact(std::span<const Symbol* const> path, SemaNarrowFactKind kind) const { return queryNarrowFact(narrowFacts_.span(), path, kind); }

    // Popped branch frames leave facts that must obey the same query rules.
    static bool                     queryNarrowFact(std::span<const SemaNarrowFact> facts, std::span<const Symbol* const> path, SemaNarrowFactKind kind);
    std::span<const SemaNarrowFact> narrowFacts() const { return narrowFacts_.span(); }
    bool                            hasNarrowFacts() const { return !narrowFacts_.empty(); }
    uint32_t                        narrowFactCount() const { return static_cast<uint32_t>(narrowFacts_.size()); }
    void                            truncateNarrowFacts(uint32_t count) { narrowFacts_.resize(count); }
    void                            clearNarrowFacts() { narrowFacts_.clear(); }
    void                            killNarrowFactsByRootId(std::span<const IdentifierRef> rootIds);

    static SymbolMap* currentSymMap(Sema& sema);
    SymbolFlags       flagsForCurrentAccess() const;

private:
    SymbolAccess     access_ = SymbolAccess::Internal;
    MemberAccessSpec memberAccess_;
    // Fill the access header instead of reserving an aligned word for each flag group.
    bool globalCompilerIfEnabled_       = true;
    bool bindingScoped_                 = false;
    bool deferBody_                     = false;
    bool ignoreRuntimeAccess_           = false;
    bool ignoreRedirectedLookupSymMaps_ = false;

    const SymbolMap* memberAccessMap_ = nullptr;

    AttributeList attributes_;

    SmallVector8<IdentifierRef> nsPath_;

    SemaCompilerIf*        compilerIf_        = nullptr;
    const SymbolImpl*      impl_              = nullptr;
    const SymbolInterface* interface_         = nullptr;
    SymbolFunction*        function_          = nullptr;
    SymbolFunction*        enclosingFunction_ = nullptr;
    SemaNamedScope*        namedScope_        = nullptr;

    SemaFrameContextFlags contextFlags_       = SemaFrameContextFlagsE::Zero;
    AstNodeRef            syntaxScopeNodeRef_ = AstNodeRef::invalid();

    SemaInlinePayload* inlinePayload_        = nullptr;
    AstNodeRef         inlineContextRootRef_ = AstNodeRef::invalid();
    uint32_t           scopeBindingCount_    = 0;

    SemaScope*                          lookupScope_              = nullptr;
    const SemaLookupScopeOverrideNodes* lookupScopeOverrideNodes_ = nullptr;
    SemaScope*                          upLookupScope_            = nullptr;

    const SymbolFunction*    deferFunction_      = nullptr;
    const SemaInlinePayload* deferInlinePayload_ = nullptr;

    BreakContext breakable_;
    BreakContext continuable_;
    AstNodeRef   scopeStmt_ = AstNodeRef::invalid();

    AstNodeRef       currentErrorScope_       = AstNodeRef::invalid();
    ErrorContextMode currentErrorContextMode_ = ErrorContextMode::None;

    AstNodeRef currentSwitch_     = AstNodeRef::invalid();
    AstNodeRef currentSwitchCase_ = AstNodeRef::invalid();

    AstNodeRef      runtimeStorageNodeRef_ = AstNodeRef::invalid();
    SymbolVariable* runtimeStorageSym_     = nullptr;

    SmallVector2<TypeRef> bindingTypes_;

    SmallVector2<SymbolVariable*> bindingVars_;

    SmallVector2<SemaIterationBorrow> iterationBorrows_;

    SmallVector4<const Symbol*> hiddenLookupSymbols_;

    SmallVector2<SemaNarrowFact> narrowFacts_;
};

SWC_END_NAMESPACE();
