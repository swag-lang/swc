#pragma once
#include "Backend/CodeGen/Micro/MachineCode.h"
#include "Backend/CodeGen/Micro/MicroBuilder.h"
#include "Backend/JIT/JITMemory.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Symbol/SymbolMap.h"

SWC_BEGIN_NAMESPACE();

class SymbolVariable;
class SymbolStruct;
class TaskContext;

enum class SymbolFunctionFlagsE : uint8_t
{
    Zero      = 0,
    Closure   = 1 << 0,
    Method    = 1 << 1,
    Throwable = 1 << 2,
    Const     = 1 << 3,
    Empty     = 1 << 4,
    Attribute = 1 << 5,
};
using SymbolFunctionFlags = EnumFlags<SymbolFunctionFlagsE>;

class SymbolFunction : public SymbolMapT<SymbolKind::Function, SymbolFunctionFlagsE>
{
public:
    static constexpr SymbolKind K = SymbolKind::Function;

    explicit SymbolFunction(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolMapT(decl, tokRef, idRef, flags)
    {
    }

    TypeRef                             returnTypeRef() const { return returnType_; }
    void                                setReturnTypeRef(TypeRef typeRef) { returnType_ = typeRef; }
    RtAttributeFlags                    rtAttributeFlags() const { return rtAttributeFlags_; }
    void                                setRtAttributeFlags(RtAttributeFlags attr) { rtAttributeFlags_ = attr; }
    const std::vector<SymbolVariable*>& parameters() const { return parameters_; }
    std::vector<SymbolVariable*>&       parameters() { return parameters_; }
    void                                addParameter(SymbolVariable* sym) { parameters_.push_back(sym); }
    Utf8                                computeName(const TaskContext& ctx) const;
    bool                                deepCompare(const SymbolFunction& otherFunc) const noexcept;
    SymbolStruct*                       ownerStruct();
    const SymbolStruct*                 ownerStruct() const;

    void             setExtraFlags(EnumFlags<AstFunctionFlagsE> parserFlags);
    bool             isClosure() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Closure); }
    bool             isMethod() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Method); }
    bool             isThrowable() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Throwable); }
    bool             isConst() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Const); }
    bool             isEmpty() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Empty); }
    bool             isAttribute() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Attribute); }
    bool             isForeign() const noexcept { return attributes().hasForeign; }
    std::string_view foreignModuleName() const { return attributes().foreignModuleName; }
    std::string_view foreignFunctionName() const { return attributes().foreignFunctionName; }
    Utf8             resolveForeignFunctionName(const TaskContext& ctx) const;

    bool     hasInterfaceMethodSlot() const noexcept { return interfaceMethodSlot_ != K_INVALID_INTERFACE_METHOD_SLOT; }
    uint32_t interfaceMethodSlot() const noexcept { return SWC_CHECK_NOT(interfaceMethodSlot_, K_INVALID_INTERFACE_METHOD_SLOT); }
    void     setInterfaceMethodSlot(uint32_t slot) noexcept { interfaceMethodSlot_ = slot; }

    SpecOpKind          specOpKind() const noexcept { return specOpKind_; }
    void                setSpecOpKind(SpecOpKind kind) noexcept { specOpKind_ = kind; }
    CallConvKind        callConvKind() const noexcept { return callConvKind_; }
    void                setCallConvKind(CallConvKind kind) noexcept { callConvKind_ = kind; }
    MicroBuilder&       microInstrBuilder(TaskContext& ctx) noexcept;
    const MicroBuilder& microInstrBuilder() const noexcept { return microInstrBuilder_; }
    AstNodeRef          declNodeRef() const noexcept { return declNodeRef_; }
    void                setDeclNodeRef(AstNodeRef nodeRef) noexcept { declNodeRef_ = nodeRef; }
    bool                tryMarkCodeGenJobScheduled() noexcept;
    void                addCallDependency(SymbolFunction* sym);
    void                appendCallDependencies(SmallVector<SymbolFunction*>& out) const;
    void*               jitEntryAddress() const noexcept { return jitEntryAddress_.load(std::memory_order_acquire); }
    void                emit(TaskContext& ctx);
    void                jit(TaskContext& ctx);

private:
    bool hasLoweredCode() const noexcept;
    bool hasJitEntryAddress() const noexcept { return jitEntryAddress() != nullptr; }
    void jitEmit(TaskContext& ctx);

    static constexpr uint32_t K_INVALID_INTERFACE_METHOD_SLOT = 0xFFFFFFFFu;

    std::vector<SymbolVariable*> parameters_;
    RtAttributeFlags             rtAttributeFlags_    = RtAttributeFlagsE::Zero;
    TypeRef                      returnType_          = TypeRef::invalid();
    SpecOpKind                   specOpKind_          = SpecOpKind::None;
    CallConvKind                 callConvKind_        = CallConvKind::Host;
    AstNodeRef                   declNodeRef_         = AstNodeRef::invalid();
    uint32_t                     interfaceMethodSlot_ = K_INVALID_INTERFACE_METHOD_SLOT;

    MicroBuilder                 microInstrBuilder_;
    MachineCode                  loweredMicroCode_;
    mutable std::mutex           callDepsMutex_;
    std::vector<SymbolFunction*> callDependencies_;
    std::mutex                   emitMutex_;
    JITMemory                jitExecMemory_;
    std::atomic<void*>           jitEntryAddress_     = nullptr;
    std::atomic<bool>            codeGenJobScheduled_ = false;
};

SWC_END_NAMESPACE();
