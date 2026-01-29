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

    void addSymbol(Symbol* sym)
    {
        for (auto* it = this; it; it = it->parent)
            it->symbols.push_back(sym);
    }
};

class SemaFrame
{
public:
    enum class BreakableKind : uint8_t
    {
        None,
        Loop,
        Switch,
    };

    struct Breakable
    {
        AstNodeRef    nodeRef = AstNodeRef::invalid();
        BreakableKind kind    = BreakableKind::None;
    };

    std::span<const IdentifierRef> nsPath() const { return nsPath_; }
    void                           pushNs(IdentifierRef id) { nsPath_.push_back(id); }
    void                           popNs() { nsPath_.pop_back(); }

    SymbolAccess         access() const { return access_; }
    void                 setAccess(SymbolAccess access) { access_ = access; }
    AttributeList&       attributes() { return attributes_; }
    const AttributeList& attributes() const { return attributes_; }

    SemaCompilerIf*                  compilerIf() const { return compilerIf_; }
    void                             setCompilerIf(SemaCompilerIf* ifc) { compilerIf_ = ifc; }
    SymbolImpl*                      impl() const { return impl_; }
    void                             setImpl(SymbolImpl* impl) { impl_ = impl; }
    SymbolInterface*                 interface() const { return interface_; }
    void                             setInterface(SymbolInterface* itf) { interface_ = itf; }
    SymbolFunction*                  function() const { return function_; }
    void                             setFunction(SymbolFunction* func) { function_ = func; }
    std::span<const TypeRef>         bindingTypes() const { return bindingTypes_.span(); }
    void                             pushBindingType(TypeRef type);
    void                             popBindingType();
    std::span<SymbolVariable* const> bindingVars() const { return bindingVars_.span(); }
    void                             pushBindingVar(SymbolVariable* sym);
    void                             popBindingVar();

    const Breakable& breakable() const { return breakable_; }
    BreakableKind    breakableKind() const { return breakable_.kind; }
    void             setBreakable(AstNodeRef nodeRef, BreakableKind kind);

    // Active switch statement (used by `case` semantic analysis).
    AstNodeRef currentSwitch() const { return currentSwitch_; }
    void       setCurrentSwitch(AstNodeRef nodeRef) { currentSwitch_ = nodeRef; }

    // Active switch case statement (used by `fallthrough` semantic analysis).
    AstNodeRef currentSwitchCase() const { return currentSwitchCase_; }
    void       setCurrentSwitchCase(AstNodeRef nodeRef) { currentSwitchCase_ = nodeRef; }

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
    Breakable                       breakable_;
    AstNodeRef                      currentSwitch_     = AstNodeRef::invalid();
    AstNodeRef                      currentSwitchCase_ = AstNodeRef::invalid();
    SmallVector<TypeRef, 2>         bindingTypes_;
    SmallVector<SymbolVariable*, 2> bindingVars_;
};

SWC_END_NAMESPACE();
