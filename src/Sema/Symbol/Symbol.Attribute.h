#pragma once
#include "Sema/Symbol/SymbolMap.h"

SWC_BEGIN_NAMESPACE();

class SymbolVariable;

class SymbolAttribute : public SymbolMapT<SymbolKind::Attribute>
{
    AttributeFlags attributes_ = AttributeFlagsE::Zero;

public:
    static constexpr auto K = SymbolKind::Attribute;

    explicit SymbolAttribute(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolMapT(decl, tokRef, idRef, flags)
    {
    }

    AttributeFlags                      attributeFlags() const { return attributes_; }
    void                                setAttributeFlags(AttributeFlags attr) { attributes_ = attr; }
    const std::vector<SymbolVariable*>& parameters() const { return parameters_; }
    std::vector<SymbolVariable*>&       parameters() { return parameters_; }
    void                                addParameter(SymbolVariable* sym) { parameters_.push_back(sym); }
    bool                                deepCompare(const SymbolAttribute& otherAttr) const noexcept;

private:
    std::vector<SymbolVariable*> parameters_;
};

SWC_END_NAMESPACE();
