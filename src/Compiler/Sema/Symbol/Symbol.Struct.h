#pragma once
#include "Compiler/Sema/Symbol/SymbolMap.h"

SWC_BEGIN_NAMESPACE();

class SymbolVariable;
class SymbolImpl;
class SymbolFunction;
class SymbolInterface;
class Sema;

enum class SpecialFuncKind : uint8_t
{
    OpBinary,
    OpUnary,
    OpAssign,
    OpIndexAssign,
    OpCast,
    OpEquals,
    OpCmp,
    OpPostCopy,
    OpPostMove,
    OpDrop,
    OpCount,
    OpData,
    OpAffect,
    OpAffectLiteral,
    OpSlice,
    OpIndex,
    OpIndexAffect,
    OpVisit,
};

enum class SymbolStructFlagsE : uint8_t
{
    Zero     = 0,
    TypeInfo = 1 << 0,
};
using SymbolStructFlags = EnumFlags<SymbolStructFlagsE>;

class SymbolStruct : public SymbolMapT<SymbolKind::Struct, SymbolStructFlagsE>
{
public:
    static constexpr auto K = SymbolKind::Struct;

    explicit SymbolStruct(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolMapT(decl, tokRef, idRef, flags)
    {
    }

    SymbolStructFlags structFlags() const noexcept { return extraFlags(); }
    uint64_t          sizeOf() const { return sizeInBytes_; }
    uint32_t          alignment() const { return alignment_; }
    Result            canBeCompleted(Sema& sema) const;

    void                                addField(SymbolVariable* sym) { fields_.push_back(sym); }
    void                                removeIgnoredFields();
    std::vector<SymbolVariable*>&       fields() { return fields_; }
    const std::vector<SymbolVariable*>& fields() const { return fields_; }

    void                     addImpl(Sema& sema, SymbolImpl& symImpl);
    std::vector<SymbolImpl*> impls() const;

    void                     addInterface(SymbolImpl& symImpl);
    Result                   addInterface(Sema& sema, SymbolImpl& symImpl);
    std::vector<SymbolImpl*> interfaces() const;
    bool                     implementsInterface(const SymbolInterface& itf) const;
    bool                     implementsInterfaceOrUsingFields(Sema& sema, const SymbolInterface& itf) const;

    void        computeLayout(Sema& sema);
    ConstantRef computeDefaultValue(Sema& sema, TypeRef typeRef);
    Result      registerSpecialFunction(Sema& sema, SymbolFunction& symFunc, SpecialFuncKind kind);

private:
    std::vector<SymbolVariable*> fields_;
    mutable std::shared_mutex    mutexImpls_;
    std::vector<SymbolImpl*>     impls_;
    mutable std::shared_mutex    mutexInterfaces_;
    std::vector<SymbolImpl*>     interfaces_;
    mutable std::shared_mutex    mutexSpecialFuncs_;
    std::vector<SymbolFunction*> specialFuncs_;
    std::once_flag               defaultStructOnce_;
    ConstantRef                  defaultStructCst_ = ConstantRef::invalid();
    uint64_t                     sizeInBytes_      = 0;
    uint32_t                     alignment_        = 0;
};

SWC_END_NAMESPACE();
