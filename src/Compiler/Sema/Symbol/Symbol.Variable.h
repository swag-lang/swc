#pragma once
#include "Compiler/Sema/Symbol/Symbol.h"

SWC_BEGIN_NAMESPACE();

enum class SymbolVariableFlagsE : uint8_t
{
    Zero              = 0,
    Let               = 1 << 0,
    Initialized       = 1 << 1,
    ExplicitUndefined = 1 << 2,
    Parameter         = 1 << 3,
    CodeGenLocalStack = 1 << 4,
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

    uint32_t    offset() const { return offset_; }
    void        setOffset(uint32_t offset) { offset_ = offset; }
    uint32_t    parameterIndex() const { return parameterIndex_; }
    bool        hasParameterIndex() const { return parameterIndex_ != K_INVALID_PARAMETER_INDEX; }
    void        setParameterIndex(uint32_t index) { parameterIndex_ = index; }
    ConstantRef cstRef() const { return cstRef_; }
    void        setCstRef(ConstantRef ref) { cstRef_ = ref; }
    ConstantRef defaultValueRef() const { return defaultValueRef_; }
    void        setDefaultValueRef(ConstantRef ref) { defaultValueRef_ = ref; }
    uint32_t    codeGenLocalSize() const { return codeGenLocalSize_; }
    void        setCodeGenLocalSize(uint32_t size) { codeGenLocalSize_ = size; }
    uint32_t    debugStackSlotOffset() const { return debugStackSlotOffset_; }
    void        setDebugStackSlotOffset(uint32_t offset) { debugStackSlotOffset_ = offset; }
    uint32_t    debugStackSlotSize() const { return debugStackSlotSize_; }
    void        setDebugStackSlotSize(uint32_t size) { debugStackSlotSize_ = size; }
    void*       codeGenPayload() const { return codeGenPayload_; }
    void        setCodeGenPayload(void* payload) const { codeGenPayload_ = payload; }
    bool        hasGlobalStorage() const { return hasGlobalStorage_; }

    void setGlobalStorage(DataSegmentKind kind, uint32_t offset)
    {
        globalStorageKind_ = kind;
        offset_            = offset;
        hasGlobalStorage_  = true;
    }

    DataSegmentKind globalStorageKind() const { return globalStorageKind_; }

private:
    uint32_t        offset_               = 0;
    uint32_t        parameterIndex_       = K_INVALID_PARAMETER_INDEX;
    ConstantRef     cstRef_               = ConstantRef::invalid();
    ConstantRef     defaultValueRef_      = ConstantRef::invalid();
    uint32_t        codeGenLocalSize_     = 0;
    uint32_t        debugStackSlotOffset_ = 0;
    uint32_t        debugStackSlotSize_   = 0;
    DataSegmentKind globalStorageKind_    = DataSegmentKind::Zero;
    bool            hasGlobalStorage_     = false;
    mutable void*   codeGenPayload_       = nullptr;
};

SWC_END_NAMESPACE();
