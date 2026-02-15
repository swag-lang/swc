#pragma once
#include "Backend/CodeGen/Micro/MicroInstrBuilder.h"
#include "Backend/JIT/JITExecMemory.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Symbol/SymbolMap.h"

SWC_BEGIN_NAMESPACE();

class SymbolVariable;
class SymbolStruct;

enum class SymbolFunctionFlagsE : uint8_t
{
    Zero      = 0,
    Closure   = 1 << 0,
    Method    = 1 << 1,
    Throwable = 1 << 2,
    Const     = 1 << 3,
    Empty     = 1 << 4,
};
using SymbolFunctionFlags = EnumFlags<SymbolFunctionFlagsE>;

class SymbolFunction : public SymbolMapT<SymbolKind::Function, SymbolFunctionFlagsE>
{
public:
    static constexpr auto K = SymbolKind::Function;

    explicit SymbolFunction(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolMapT(decl, tokRef, idRef, flags)
    {
    }

    TypeRef                             returnTypeRef() const { return returnType_; }
    void                                setReturnTypeRef(TypeRef typeRef) { returnType_ = typeRef; }
    const std::vector<SymbolVariable*>& parameters() const { return parameters_; }
    std::vector<SymbolVariable*>&       parameters() { return parameters_; }
    void                                addParameter(SymbolVariable* sym) { parameters_.push_back(sym); }
    Utf8                                computeName(const TaskContext& ctx) const;
    bool                                deepCompare(const SymbolFunction& otherFunc) const noexcept;
    SymbolStruct*                       ownerStruct();
    const SymbolStruct*                 ownerStruct() const;

    void setExtraFlags(EnumFlags<AstFunctionFlagsE> parserFlags);
    bool isClosure() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Closure); }
    bool isMethod() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Method); }
    bool isThrowable() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Throwable); }
    bool isConst() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Const); }
    bool isEmpty() const noexcept { return hasExtraFlag(SymbolFunctionFlagsE::Empty); }

    bool     hasInterfaceMethodSlot() const noexcept { return interfaceMethodSlot_ != K_INVALID_INTERFACE_METHOD_SLOT; }
    uint32_t interfaceMethodSlot() const noexcept { return SWC_CHECK_NOT(interfaceMethodSlot_, K_INVALID_INTERFACE_METHOD_SLOT); }
    void     setInterfaceMethodSlot(uint32_t slot) noexcept { interfaceMethodSlot_ = slot; }

    SpecOpKind               specOpKind() const noexcept { return specOpKind_; }
    void                     setSpecOpKind(SpecOpKind kind) noexcept { specOpKind_ = kind; }
    CallConvKind             callConvKind() const noexcept { return callConvKind_; }
    void                     setCallConvKind(CallConvKind kind) noexcept { callConvKind_ = kind; }
    MicroInstrBuilder&       microInstrBuilder(TaskContext& ctx) noexcept;
    const MicroInstrBuilder& microInstrBuilder() const noexcept { return microInstrBuilder_; }
    AstNodeRef               declNodeRef() const noexcept { return declNodeRef_; }
    void                     setDeclNodeRef(AstNodeRef nodeRef) noexcept { declNodeRef_ = nodeRef; }
    bool                     tryMarkCodeGenJobScheduled() noexcept;
    void                     addCallDependency(SymbolFunction* sym);
    void                     appendCallDependencies(SmallVector<SymbolFunction*>& out) const;
    uint64_t                 entryAddress() const noexcept { return entryAddress_.load(std::memory_order_acquire); }
    bool                     hasEntryAddress() const noexcept { return entryAddress() != 0; }
    void                     emit(TaskContext& ctx);

private:
    static constexpr uint32_t K_INVALID_INTERFACE_METHOD_SLOT = 0xFFFFFFFFu;

    std::vector<SymbolVariable*> parameters_;
    TypeRef                      returnType_          = TypeRef::invalid();
    SpecOpKind                   specOpKind_          = SpecOpKind::None;
    CallConvKind                 callConvKind_        = CallConvKind::Host;
    AstNodeRef                   declNodeRef_         = AstNodeRef::invalid();
    uint32_t                     interfaceMethodSlot_ = K_INVALID_INTERFACE_METHOD_SLOT;

    MicroInstrBuilder            microInstrBuilder_;
    mutable std::mutex           callDepsMutex_;
    std::vector<SymbolFunction*> callDependencies_;
    std::mutex                   jitMutex_;
    JITExecMemory                jitExecMemory_;
    std::atomic<uint64_t>        entryAddress_     = 0;
    std::atomic<bool>            codeGenJobScheduled_ = false;
};

SWC_END_NAMESPACE();
