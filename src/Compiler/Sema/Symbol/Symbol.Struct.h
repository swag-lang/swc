#pragma once
#include "Compiler/Sema/Generic/GenericSemaGate.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Symbol/SymbolMap.h"

SWC_BEGIN_NAMESPACE();

class SymbolVariable;
class SymbolImpl;
class SymbolFunction;
class SymbolInterface;
class Sema;

enum class SymbolStructFlagsE : uint8_t
{
    Zero     = 0,
    TypeInfo = 1 << 0,
};
using SymbolStructFlags = EnumFlags<SymbolStructFlagsE>;

class SymbolStruct : public SymbolMapT<SymbolKind::Struct, SymbolStructFlagsE>
{
public:
    struct GenericArgKey
    {
        TypeRef     typeRef = TypeRef::invalid();
        ConstantRef cstRef  = ConstantRef::invalid();

        bool operator==(const GenericArgKey& other) const noexcept
        {
            return typeRef == other.typeRef && cstRef == other.cstRef;
        }
    };

    static constexpr auto K = SymbolKind::Struct;

    explicit SymbolStruct(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolMapT(decl, tokRef, idRef, flags)
    {
    }

    SymbolStructFlags structFlags() const noexcept { return extraFlags(); }
    uint64_t          sizeOf() const { return sizeInBytes_; }
    uint32_t          alignment() const { return alignment_; }
    AstNodeRef        declNodeRef() const noexcept { return declNodeRef_; }
    void              setDeclNodeRef(AstNodeRef nodeRef) noexcept { declNodeRef_ = nodeRef; }
    Result            canBeCompleted(Sema& sema) const;
    Result            registerSpecOps(Sema& sema) const;

    void                                addField(SymbolVariable* sym);
    void                                removeIgnoredFields();
    std::vector<SymbolVariable*>&       fields() { return fields_; }
    const std::vector<SymbolVariable*>& fields() const { return fields_; }

    void                     addImpl(Sema& sema, SymbolImpl& symImpl);
    std::vector<SymbolImpl*> impls() const;

    void                     addInterface(SymbolImpl& symImpl);
    Result                   addInterface(Sema& sema, SymbolImpl& symImpl);
    std::vector<SymbolImpl*> interfaces() const;
    const SymbolImpl*        findInterfaceImpl(IdentifierRef interfaceIdRef) const;
    bool                     implementsInterface(const SymbolInterface& itf) const;
    bool                     implementsInterfaceOrUsingFields(Sema& sema, const SymbolInterface& itf) const;

    Result      computeLayout(TaskContext& ctx);
    ConstantRef computeDefaultValue(Sema& sema, TypeRef typeRef);

    SmallVector<SymbolFunction*> getSpecOp(IdentifierRef identifierRef) const;
    Result                       registerSpecOp(SymbolFunction& symFunc, SpecOpKind kind);
    const SymbolFunction*        opDrop() const { return opDrop_; }
    const SymbolFunction*        opPostCopy() const { return opPostCopy_; }
    const SymbolFunction*        opPostMove() const { return opPostMove_; }

    bool                isGenericRoot() const noexcept { return genericRoot_; }
    void                setGenericRoot(bool value) noexcept { genericRoot_ = value; }
    bool                isGenericInstance() const noexcept { return genericInstance_; }
    void                setGenericInstance(SymbolStruct* root) noexcept;
    SymbolStruct*       genericRootSym() noexcept { return genericRootSym_; }
    const SymbolStruct* genericRootSym() const noexcept { return genericRootSym_; }
    SymbolStruct*       findGenericInstance(std::span<const GenericArgKey> args) const;
    SymbolStruct*       addGenericInstance(std::span<const GenericArgKey> args, SymbolStruct* instance);
    bool                tryGetGenericInstanceArgs(const SymbolStruct& instance, SmallVector<GenericArgKey>& outArgs) const;
    bool                beginGenericSema() const;
    void                endGenericSema() const;

private:
    struct GenericInstanceEntry
    {
        SmallVector<GenericArgKey> args;
        SymbolStruct*              symbol = nullptr;
    };

    std::vector<SymbolVariable*>      fields_;
    mutable std::shared_mutex         mutexImpls_;
    std::vector<SymbolImpl*>          impls_;
    mutable std::shared_mutex         mutexInterfaces_;
    std::vector<SymbolImpl*>          interfaces_;
    mutable std::shared_mutex         mutexSpecOps_;
    std::vector<SymbolFunction*>      specOps_;
    mutable std::mutex                genericMutex_;
    std::vector<GenericInstanceEntry> genericInstances_;
    mutable GenericSemaGate           genericSema_;
    SymbolFunction*                   opDrop_     = nullptr;
    SymbolFunction*                   opPostCopy_ = nullptr;
    SymbolFunction*                   opPostMove_ = nullptr;
    std::once_flag                    defaultStructOnce_;
    ConstantRef                       defaultStructCst_ = ConstantRef::invalid();
    uint64_t                          sizeInBytes_      = 0;
    uint32_t                          alignment_        = 0;
    AstNodeRef                        declNodeRef_      = AstNodeRef::invalid();
    bool                              genericRoot_      = false;
    bool                              genericInstance_  = false;
    SymbolStruct*                     genericRootSym_   = nullptr;
};

SWC_END_NAMESPACE();
