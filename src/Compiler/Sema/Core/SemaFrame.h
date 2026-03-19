#pragma once
#include "Compiler/Parser/Ast/AstNode.h"
#include "Compiler/Sema/Core/AttributeList.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.h"

SWC_BEGIN_NAMESPACE();

class SymbolEnum;
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

enum class SemaFrameContextFlagsE
{
    Zero             = 0,
    RunExpr          = 1 << 0,
    RequireConstExpr = 1 << 1,
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

    SemaCompilerIf*          currentCompilerIf() const { return compilerIf_; }
    void                     setCurrentCompilerIf(SemaCompilerIf* ifc) { compilerIf_ = ifc; }
    SymbolImpl*              currentImpl() const { return impl_; }
    void                     setCurrentImpl(SymbolImpl* impl) { impl_ = impl; }
    SymbolInterface*         currentInterface() const { return interface_; }
    void                     setCurrentInterface(SymbolInterface* itf) { interface_ = itf; }
    SymbolFunction*          currentFunction() const { return function_; }
    void                     setCurrentFunction(SymbolFunction* func) { function_ = func; }
    SemaFrameContextFlags    contextFlags() const { return contextFlags_; }
    bool                     hasContextFlag(SemaFrameContextFlagsE flag) const { return contextFlags_.has(flag); }
    void                     addContextFlag(SemaFrameContextFlagsE flag) { contextFlags_.add(flag); }
    void                     removeContextFlag(SemaFrameContextFlagsE flag) { contextFlags_.remove(flag); }
    const SemaInlinePayload* currentInlinePayload() const { return inlinePayload_; }
    void                     setCurrentInlinePayload(const SemaInlinePayload* payload) { inlinePayload_ = payload; }

    const BreakContext& currentBreakContext() const { return breakable_; }
    void                setCurrentBreakContent(AstNodeRef nodeRef, BreakContextKind kind);
    BreakContextKind    currentBreakableKind() const { return breakable_.kind; }
    AstNodeRef          currentSwitch() const { return currentSwitch_; }
    void                setCurrentSwitch(AstNodeRef nodeRef) { currentSwitch_ = nodeRef; }
    AstNodeRef          currentSwitchCase() const { return currentSwitchCase_; }
    void                setCurrentSwitchCase(AstNodeRef nodeRef) { currentSwitchCase_ = nodeRef; }
    AstNodeRef          currentRuntimeStorageNodeRef() const { return runtimeStorageNodeRef_; }
    SymbolVariable*     currentRuntimeStorageSym() const { return runtimeStorageSym_; }
    void                setCurrentRuntimeStorage(AstNodeRef nodeRef, SymbolVariable* sym)
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

    static SymbolMap* currentSymMap(Sema& sema);
    SymbolFlags       flagsForCurrentAccess() const;

private:
    SymbolAccess                  access_                  = SymbolAccess::ModulePrivate;
    bool                          globalCompilerIfEnabled_ = true;
    AttributeList                 attributes_;
    SmallVector8<IdentifierRef>   nsPath_;
    SemaCompilerIf*               compilerIf_    = nullptr;
    SymbolImpl*                   impl_          = nullptr;
    SymbolInterface*              interface_     = nullptr;
    SymbolFunction*               function_      = nullptr;
    SemaFrameContextFlags         contextFlags_  = SemaFrameContextFlagsE::Zero;
    const SemaInlinePayload*      inlinePayload_ = nullptr;
    BreakContext                  breakable_;
    AstNodeRef                    currentSwitch_     = AstNodeRef::invalid();
    AstNodeRef                    currentSwitchCase_ = AstNodeRef::invalid();
    AstNodeRef                    runtimeStorageNodeRef_ = AstNodeRef::invalid();
    SymbolVariable*               runtimeStorageSym_     = nullptr;
    SmallVector2<TypeRef>         bindingTypes_;
    SmallVector2<SymbolVariable*> bindingVars_;
};

SWC_END_NAMESPACE();
