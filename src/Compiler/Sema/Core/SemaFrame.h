#pragma once
#include "Compiler/Parser/Ast/AstNode.h"
#include "Compiler/Sema/Core/AttributeList.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include <unordered_set>

SWC_BEGIN_NAMESPACE();

class SymbolEnum;
class SemaScope;
class Ast;
struct SemaInlinePayload;

struct SemaCompilerIf
{
    std::vector<Symbol*> symbols;
    SemaCompilerIf*      parent = nullptr;

    void addSymbolToChain(Symbol* sym)
    {
        for (auto it = this; it; it = it->parent)
            it->symbols.push_back(sym);
    }
};

struct SemaNamedCompilerScope
{
    IdentifierRef           idRef    = IdentifierRef::invalid();
    AstNodeRef              scopeRef = AstNodeRef::invalid();
    SemaNamedCompilerScope* parent   = nullptr;
};

struct SemaLookupScopeOverrideNodes
{
    const Ast*                     ast = nullptr;
    std::unordered_set<AstNodeRef> nodeRefs;
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

class SemaFrame
{
public:
    enum class BreakContextKind : uint8_t
    {
        None,
        Scope,
        Loop,
        Switch,
    };

    enum class ErrorContextMode : uint8_t
    {
        None,
        Try,
        Catch,
        TryCatch,
        Assume,
    };

    struct BreakContext
    {
        AstNodeRef       nodeRef = AstNodeRef::invalid();
        BreakContextKind kind    = BreakContextKind::None;
    };

    std::span<const IdentifierRef> nsPath() const { return nsPath_; }
    void                           pushNs(IdentifierRef id) { nsPath_.push_back(id); }
    void                           popNs() { nsPath_.pop_back(); }

    SymbolAccess         currentAccess() const { return access_; }
    void                 setCurrentAccess(SymbolAccess access) { access_ = access; }
    bool                 globalCompilerIfEnabled() const { return globalCompilerIfEnabled_; }
    void                 setGlobalCompilerIfEnabled(bool value) { globalCompilerIfEnabled_ = value; }
    AttributeList&       currentAttributes() { return attributes_; }
    const AttributeList& currentAttributes() const { return attributes_; }

    SemaCompilerIf*                     currentCompilerIf() const { return compilerIf_; }
    void                                setCurrentCompilerIf(SemaCompilerIf* ifc) { compilerIf_ = ifc; }
    const SymbolImpl*                   currentImpl() const { return impl_; }
    void                                setCurrentImpl(const SymbolImpl* impl) { impl_ = impl; }
    const SymbolInterface*              currentInterface() const { return interface_; }
    void                                setCurrentInterface(const SymbolInterface* itf) { interface_ = itf; }
    SymbolFunction*                     currentFunction() const { return function_; }
    void                                setCurrentFunction(SymbolFunction* func) { function_ = func; }
    SymbolFunction*                     enclosingFunction() const { return enclosingFunction_; }
    void                                setEnclosingFunction(SymbolFunction* func) { enclosingFunction_ = func; }
    SemaNamedCompilerScope*             currentNamedCompilerScope() const { return namedCompilerScope_; }
    void                                setCurrentNamedCompilerScope(SemaNamedCompilerScope* scope) { namedCompilerScope_ = scope; }
    SemaFrameContextFlags               contextFlags() const { return contextFlags_; }
    bool                                hasContextFlag(SemaFrameContextFlagsE flag) const { return contextFlags_.has(flag); }
    void                                addContextFlag(SemaFrameContextFlagsE flag) { contextFlags_.add(flag); }
    void                                removeContextFlag(SemaFrameContextFlagsE flag) { contextFlags_.remove(flag); }
    AstNodeRef                          syntaxScopeNodeRef() const { return syntaxScopeNodeRef_; }
    void                                setSyntaxScopeNodeRef(AstNodeRef nodeRef) { syntaxScopeNodeRef_ = nodeRef; }
    SemaInlinePayload*                  currentInlinePayload() { return inlinePayload_; }
    const SemaInlinePayload*            currentInlinePayload() const { return inlinePayload_; }
    void                                setCurrentInlinePayload(SemaInlinePayload* payload) { inlinePayload_ = payload; }
    AstNodeRef                          inlineContextRootRef() const { return inlineContextRootRef_; }
    void                                setInlineContextRootRef(AstNodeRef nodeRef) { inlineContextRootRef_ = nodeRef; }
    SemaScope*                          lookupScope() const { return lookupScope_; }
    void                                setLookupScope(SemaScope* scope) { lookupScope_ = scope; }
    const SemaLookupScopeOverrideNodes* lookupScopeOverrideNodes() const { return lookupScopeOverrideNodes_; }
    void                                setLookupScopeOverrideNodes(const SemaLookupScopeOverrideNodes* nodes) { lookupScopeOverrideNodes_ = nodes; }
    SemaScope*                          upLookupScope() const { return upLookupScope_; }
    void                                setUpLookupScope(SemaScope* scope) { upLookupScope_ = scope; }
    bool                                ignoreRuntimeAccess() const { return ignoreRuntimeAccess_; }
    void                                setIgnoreRuntimeAccess(bool value) { ignoreRuntimeAccess_ = value; }

    const BreakContext& currentBreakContext() const { return breakable_; }
    void                setCurrentBreakContent(AstNodeRef nodeRef, BreakContextKind kind);
    BreakContextKind    currentBreakableKind() const { return breakable_.kind; }
    AstNodeRef          currentErrorScope() const { return currentErrorScope_; }
    ErrorContextMode    currentErrorContextMode() const { return currentErrorContextMode_; }
    void                setCurrentErrorContext(AstNodeRef nodeRef, ErrorContextMode mode)
    {
        currentErrorScope_       = nodeRef;
        currentErrorContextMode_ = mode;
    }
    TypeRef         currentLoopIndexTypeRef() const { return currentLoopIndexTypeRef_; }
    void            setCurrentLoopIndexTypeRef(TypeRef typeRef) { currentLoopIndexTypeRef_ = typeRef; }
    AstNodeRef      currentLoopIndexOwnerRef() const { return currentLoopIndexOwnerRef_; }
    void            setCurrentLoopIndexOwnerRef(AstNodeRef nodeRef) { currentLoopIndexOwnerRef_ = nodeRef; }
    AstNodeRef      currentSwitch() const { return currentSwitch_; }
    void            setCurrentSwitch(AstNodeRef nodeRef) { currentSwitch_ = nodeRef; }
    AstNodeRef      currentSwitchCase() const { return currentSwitchCase_; }
    void            setCurrentSwitchCase(AstNodeRef nodeRef) { currentSwitchCase_ = nodeRef; }
    AstNodeRef      currentRuntimeStorageNodeRef() const { return runtimeStorageNodeRef_; }
    SymbolVariable* currentRuntimeStorageSym() const { return runtimeStorageSym_; }
    void            setCurrentRuntimeStorage(AstNodeRef nodeRef, SymbolVariable* sym)
    {
        runtimeStorageNodeRef_ = nodeRef;
        runtimeStorageSym_     = sym;
    }

    std::span<const TypeRef>         bindingTypes() const { return bindingTypes_.span(); }
    void                             pushBindingType(TypeRef type);
    void                             popBindingType();
    std::span<SymbolVariable* const> bindingVars() const { return bindingVars_.span(); }
    void                             pushBindingVar(SymbolVariable* sym);
    void                             popBindingVar();
    void                             hideLookupSymbol(const Symbol* sym);
    bool                             isLookupSymbolHidden(const Symbol* sym) const;

    static SymbolMap* currentSymMap(Sema& sema);
    SymbolFlags       flagsForCurrentAccess() const;

private:
    SymbolAccess                        access_                  = SymbolAccess::ModulePrivate;
    bool                                globalCompilerIfEnabled_ = true;
    AttributeList                       attributes_;
    SmallVector8<IdentifierRef>         nsPath_;
    SemaCompilerIf*                     compilerIf_               = nullptr;
    const SymbolImpl*                   impl_                     = nullptr;
    const SymbolInterface*              interface_                = nullptr;
    SymbolFunction*                     function_                 = nullptr;
    SymbolFunction*                     enclosingFunction_        = nullptr;
    SemaNamedCompilerScope*             namedCompilerScope_       = nullptr;
    SemaFrameContextFlags               contextFlags_             = SemaFrameContextFlagsE::Zero;
    AstNodeRef                          syntaxScopeNodeRef_       = AstNodeRef::invalid();
    SemaInlinePayload*                  inlinePayload_            = nullptr;
    AstNodeRef                          inlineContextRootRef_     = AstNodeRef::invalid();
    SemaScope*                          lookupScope_              = nullptr;
    const SemaLookupScopeOverrideNodes* lookupScopeOverrideNodes_ = nullptr;
    SemaScope*                          upLookupScope_            = nullptr;
    bool                                ignoreRuntimeAccess_      = false;
    BreakContext                        breakable_;
    AstNodeRef                          currentErrorScope_        = AstNodeRef::invalid();
    ErrorContextMode                    currentErrorContextMode_  = ErrorContextMode::None;
    TypeRef                             currentLoopIndexTypeRef_  = TypeRef::invalid();
    AstNodeRef                          currentLoopIndexOwnerRef_ = AstNodeRef::invalid();
    AstNodeRef                          currentSwitch_            = AstNodeRef::invalid();
    AstNodeRef                          currentSwitchCase_        = AstNodeRef::invalid();
    AstNodeRef                          runtimeStorageNodeRef_    = AstNodeRef::invalid();
    SymbolVariable*                     runtimeStorageSym_        = nullptr;
    SmallVector2<TypeRef>               bindingTypes_;
    SmallVector2<SymbolVariable*>       bindingVars_;
    SmallVector4<const Symbol*>         hiddenLookupSymbols_;
};

SWC_END_NAMESPACE();
