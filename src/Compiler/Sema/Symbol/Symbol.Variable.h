#pragma once
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Support/Core/DataSegment.h"
#include "Support/Core/Flags.h"
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

class SymbolFunction;

enum class SymbolVariableFlagsE : uint16_t
{
    Zero                    = 0,
    Let                     = 1 << 0,
    Initialized             = 1 << 1,
    DefaultInitElided       = 1 << 2,
    Parameter               = 1 << 3,
    CodeGenLocalStack       = 1 << 4,
    FunctionLocal           = 1 << 5,
    RetVal                  = 1 << 6,
    NeedsAddressableStorage = 1 << 7,
    CallerLocationDefault   = 1 << 8,
    NeedsDefiniteInit       = 1 << 9,
    RuntimeStorage          = 1 << 10,
    ClosureCaptureByRef     = 1 << 11,
    GlobalStorage           = 1 << 12,
    FwdCopy                 = 1 << 13, // copy variant of a '#fwd' parameter: requires a copyable type at match time
    ClosureCapture          = 1 << 14,
    LateInit                = 1 << 15, // 'late' field: non-null type, null storage until first assignment
};
using SymbolVariableFlags = EnumFlags<SymbolVariableFlagsE>;

class SymbolVariable : public SymbolT<SymbolKind::Variable, SymbolVariableFlagsE>
{
public:
    static constexpr auto     K                         = SymbolKind::Variable;
    static constexpr uint32_t K_INVALID_PARAMETER_INDEX = 0xFFFFFFFFu;
    explicit SymbolVariable(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolT(decl, tokRef, idRef, flags)
    {
    }

    uint32_t              offset() const { return offset_; }
    void                  setOffset(uint32_t offset) { offset_ = offset; }
    uint32_t              parameterIndex() const { return parameterIndex_; }
    bool                  hasParameterIndex() const { return parameterIndex_ != K_INVALID_PARAMETER_INDEX; }
    void                  setParameterIndex(uint32_t index) { parameterIndex_ = index; }
    ConstantRef           cstRef() const { return cstRef_; }
    void                  setCstRef(ConstantRef ref) { cstRef_ = ref; }
    ConstantRef           defaultValueRef() const { return defaultValueRef_; }
    void                  setDefaultValueRef(ConstantRef ref) { defaultValueRef_ = ref; }
    uint32_t              codeGenLocalSize() const { return codeGenLocalSize_; }
    void                  setCodeGenLocalSize(uint32_t size) { codeGenLocalSize_ = size; }
    uint32_t              debugStackSlotOffset() const { return debugStackSlotOffset_; }
    void                  setDebugStackSlotOffset(uint32_t offset) { debugStackSlotOffset_ = offset; }
    uint32_t              debugStackSlotSize() const { return debugStackSlotSize_; }
    void                  setDebugStackSlotSize(uint32_t size) { debugStackSlotSize_ = size; }
    bool                  isClosureCapture() const noexcept { return hasExtraFlag(SymbolVariableFlagsE::ClosureCapture); }
    SymbolVariable*       closureCapturedSource() const noexcept { return closureCapturedSource_; }
    void                  setClosureCapturedSource(SymbolVariable* source) noexcept;
    uint32_t              closureCaptureOffset() const noexcept { return closureCaptureOffset_; }
    void                  setClosureCaptureOffset(uint32_t offset) noexcept { closureCaptureOffset_ = offset; }
    bool                  closureCaptureByRef() const noexcept { return hasExtraFlag(SymbolVariableFlagsE::ClosureCaptureByRef); }
    void                  setClosureCaptureByRef(bool value) noexcept;
    bool                  hasGlobalStorage() const { return hasExtraFlag(SymbolVariableFlagsE::GlobalStorage); }
    bool                  isDeclaredGlobal() const noexcept { return declaredGlobal_; }
    void                  setDeclaredGlobal(bool value) noexcept { declaredGlobal_ = value; }
    bool                  isDeclaredThreadLocal() const noexcept { return declaredThreadLocal_; }
    void                  setDeclaredThreadLocal(bool value) noexcept { declaredThreadLocal_ = value; }
    SymbolFunction*       globalFunctionInit() const { return globalFunctionInit_; }
    void                  setGlobalFunctionInit(SymbolFunction* symbol) { globalFunctionInit_ = symbol; }
    const SymbolFunction* ownerFunction() const noexcept;
    bool                  isFunctionLocalVariable() const noexcept { return ownerFunction() != nullptr; }
    bool                  isFunctionLocalVariable(const SymbolFunction& function) const noexcept { return ownerFunction() == &function; }
    bool                  isUsingField() const noexcept;
    const SymbolStruct*   usingTargetStruct(const TaskContext& ctx) const;
    const SymbolStruct*   usingTargetStruct(const TaskContext& ctx, bool& outIsPointer) const;
    void                  setGlobalStorage(DataSegmentKind kind, uint32_t offset);
    DataSegmentKind       globalStorageKind() const { return globalStorageKind_; }

    // A 'tls' global. Its global storage holds the value every thread starts from, and the
    // address a use resolves to is the calling thread's own copy of it, so the address is not a
    // link-time constant and has to be materialized by a call.
    bool     isThreadLocal() const noexcept { return threadLocalSize_ != 0; }
    uint32_t threadLocalSize() const noexcept { return threadLocalSize_; }
    uint32_t threadLocalIdOffset() const noexcept { return threadLocalIdOffset_; }
    void     setThreadLocalStorage(uint32_t idOffset, uint32_t size) noexcept
    {
        threadLocalIdOffset_ = idOffset;
        threadLocalSize_     = size;
    }

    MemberAccess memberAccess() const noexcept { return memberAccess_; }
    void         setMemberAccess(MemberAccess access) noexcept { memberAccess_ = access; }

    // 'readonly' rides on top of the access level instead of replacing it, so a field keeps the
    // reads its level grants and gives up the writes its level would have granted outside the type.
    bool isMemberReadOnly() const noexcept { return memberReadOnly_; }
    void setMemberReadOnly(bool value) noexcept { memberReadOnly_ = value; }

private:
    uint32_t        offset_                = 0;
    uint32_t        parameterIndex_        = K_INVALID_PARAMETER_INDEX;
    ConstantRef     cstRef_                = ConstantRef::invalid();
    ConstantRef     defaultValueRef_       = ConstantRef::invalid();
    uint32_t        codeGenLocalSize_      = 0;
    uint32_t        debugStackSlotOffset_  = 0;
    uint32_t        debugStackSlotSize_    = 0;
    DataSegmentKind globalStorageKind_     = DataSegmentKind::Zero;
    SymbolFunction* globalFunctionInit_    = nullptr;
    SymbolVariable* closureCapturedSource_ = nullptr;
    uint32_t        closureCaptureOffset_  = 0;
    uint32_t        threadLocalIdOffset_   = 0;
    uint32_t        threadLocalSize_       = 0;
    bool            declaredGlobal_        = false;
    bool            declaredThreadLocal_   = false;
    MemberAccess    memberAccess_          = MemberAccess::Internal;
    bool            memberReadOnly_        = false;
};

SWC_END_NAMESPACE();
