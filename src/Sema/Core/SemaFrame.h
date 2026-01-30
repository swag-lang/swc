#pragma once
#include "Parser/Ast/AstNode.h"
#include "Sema/Core/AttributeList.h"
#include "Sema/Symbol/Symbol.Struct.h"
#include "Sema/Symbol/Symbol.h"

SWC_BEGIN_NAMESPACE();

class SymbolEnum;

struct SemaCompilerIf
{
    std::vector<Symbol*> symbols;
    SemaCompilerIf*      parent = nullptr;

    void addSymbolToChain(Symbol* sym)
    {
        for (auto* it = this; it; it = it->parent)
            it->symbols.push_back(sym);
    }
};

class SemaFrame
{
public:
    enum class BreakContextKind : uint8_t
    {
        None,
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
    AttributeList&       currentAttributes() { return attributes_; }
    const AttributeList& currentAttributes() const { return attributes_; }

    SemaCompilerIf*  currentCompilerIf() const { return compilerIf_; }
    void             setCurrentCompilerIf(SemaCompilerIf* ifc) { compilerIf_ = ifc; }
    SymbolImpl*      currentImpl() const { return impl_; }
    void             setCurrentImpl(SymbolImpl* impl) { impl_ = impl; }
    SymbolInterface* currentInterface() const { return interface_; }
    void             setCurrentInterface(SymbolInterface* itf) { interface_ = itf; }
    SymbolFunction*  currentFunction() const { return function_; }
    void             setCurrentFunction(SymbolFunction* func) { function_ = func; }

    const BreakContext& currentBreakContext() const { return breakable_; }
    void                setCurrentBreakContent(AstNodeRef nodeRef, BreakContextKind kind);
    BreakContextKind    currentBreakableKind() const { return breakable_.kind; }
    AstNodeRef          currentSwitch() const { return currentSwitch_; }
    void                setCurrentSwitch(AstNodeRef nodeRef) { currentSwitch_ = nodeRef; }
    AstNodeRef          currentSwitchCase() const { return currentSwitchCase_; }
    void                setCurrentSwitchCase(AstNodeRef nodeRef) { currentSwitchCase_ = nodeRef; }

    std::span<const TypeRef>         bindingTypes() const { return bindingTypes_.span(); }
    void                             pushBindingType(TypeRef type);
    void                             popBindingType();
    std::span<SymbolVariable* const> bindingVars() const { return bindingVars_.span(); }
    void                             pushBindingVar(SymbolVariable* sym);
    void                             popBindingVar();

    static SymbolMap* currentSymMap(Sema& sema);
    SymbolFlags       flagsForCurrentAccess() const;

private:
    SymbolAccess                    access_ = SymbolAccess::Private;
    AttributeList                   attributes_;
    SmallVector<IdentifierRef, 8>   nsPath_;
    SemaCompilerIf*                 compilerIf_ = nullptr;
    SymbolImpl*                     impl_       = nullptr;
    SymbolInterface*                interface_  = nullptr;
    SymbolFunction*                 function_   = nullptr;
    BreakContext                    breakable_;
    AstNodeRef                      currentSwitch_     = AstNodeRef::invalid();
    AstNodeRef                      currentSwitchCase_ = AstNodeRef::invalid();
    SmallVector<TypeRef, 2>         bindingTypes_;
    SmallVector<SymbolVariable*, 2> bindingVars_;
};

SWC_END_NAMESPACE();
