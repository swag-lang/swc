#pragma once
#include "Compiler/Sema/Symbol/SymbolMap.h"

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

    RtAttributeFlags                    rtAttributeFlags() const { return rtAttributes_; }
    void                                setRtAttributeFlags(RtAttributeFlags attr) { rtAttributes_ = attr; }
    const std::vector<SymbolVariable*>& parameters() const { return parameters_; }
    std::vector<SymbolVariable*>&       parameters() { return parameters_; }
    void                                addParameter(SymbolVariable* sym) { parameters_.push_back(sym); }
    bool                                deepCompare(const SymbolAttribute& otherAttr) const noexcept;

private:
    std::vector<SymbolVariable*> parameters_;
    RtAttributeFlags             rtAttributes_ = RtAttributeFlagsE::Zero;
};

SWC_END_NAMESPACE();
