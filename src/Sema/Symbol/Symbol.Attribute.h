#pragma once
#include "Sema/Symbol/SymbolMap.h"

SWC_BEGIN_NAMESPACE();

class SymbolVariable;

class SymbolAttribute : public SymbolMapT<SymbolKind::Attribute>
{
public:
    static constexpr auto K = SymbolKind::Attribute;

    explicit SymbolAttribute(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolMapT(decl, tokRef, idRef, flags)
    {
    }

    SwagAttributeFlags                  rtAttributeFlags() const { return rtAttributes_; }
    void                                setRtAttributeFlags(SwagAttributeFlags attr) { rtAttributes_ = attr; }
    const std::vector<SymbolVariable*>& parameters() const { return parameters_; }
    std::vector<SymbolVariable*>&       parameters() { return parameters_; }
    void                                addParameter(SymbolVariable* sym) { parameters_.push_back(sym); }
    bool                                deepCompare(const SymbolAttribute& otherAttr) const noexcept;

private:
    std::vector<SymbolVariable*> parameters_;
    SwagAttributeFlags           rtAttributes_ = SwagAttributeFlagsE::Zero;
};

SWC_END_NAMESPACE();
