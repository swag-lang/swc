#pragma once
#include "Compiler/Lexer/SourceCodeRange.h"
#include "Compiler/Parser/Ast/AstNodeId.h"
#include "Support/Core/PagedStore.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();
class TypeInfo;
class Sema;
class CodeGen;
class Ast;
class SourceFile;
class TaskContext;
class ConstantValue;
struct SourceCodeRange;
struct CloneContext
{
};

enum class AstModifierFlagsE : uint32_t
{
    Zero     = 0,
    Bit      = 1 << 0,
    UnConst  = 1 << 1,
    Err      = 1 << 2,
    NoErr    = 1 << 3,
    Promote  = 1 << 4,
    Wrap     = 1 << 5,
    NoDrop   = 1 << 6,
    Ref      = 1 << 7,
    ConstRef = 1 << 8,
    Reverse  = 1 << 9,
    Move     = 1 << 10,
    MoveRaw  = 1 << 11,
    Nullable = 1 << 12,
    Count,
};
using AstModifierFlags = EnumFlags<AstModifierFlagsE>;

struct AstNode
{
    AstNode() = default;

    AstNode(const AstNode& other) :
        id_(other.id_),
        parserFlags_(other.parserFlags_),
        codeRef_(other.codeRef_)
    {
        payloadStorage_.store(other.payloadStorage_.load(std::memory_order_relaxed), std::memory_order_relaxed);
    }

    AstNode& operator=(const AstNode& other)
    {
        if (this != &other)
        {
            payloadStorage_.store(other.payloadStorage_.load(std::memory_order_relaxed), std::memory_order_relaxed);
            id_          = other.id_;
            parserFlags_ = other.parserFlags_;
            codeRef_     = other.codeRef_;
        }

        return *this;
    }

    AstNode(AstNode&& other) noexcept :
        id_(other.id_),
        parserFlags_(other.parserFlags_),
        codeRef_(other.codeRef_)
    {
        payloadStorage_.store(other.payloadStorage_.load(std::memory_order_relaxed), std::memory_order_relaxed);
    }

    AstNode& operator=(AstNode&& other) noexcept
    {
        if (this != &other)
        {
            payloadStorage_.store(other.payloadStorage_.load(std::memory_order_relaxed), std::memory_order_relaxed);
            id_          = other.id_;
            parserFlags_ = other.parserFlags_;
            codeRef_     = other.codeRef_;
        }

        return *this;
    }

    // ReSharper disable once CppPossiblyUninitializedMember
    explicit AstNode(AstNodeId nodeId, const SourceCodeRef& codeRef) :
        id_(nodeId),
        codeRef_(codeRef)
    {
    }

    using ParserFlags = uint8_t;

    void clearFlags()
    {
        parserFlags_ = 0;
        clearPayload();
    }

    static void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast, SpanRef spanRef);
    static void collectChildren(SmallVector<AstNodeRef>& out, std::initializer_list<AstNodeRef> nodes);
    void        collectChildrenFromAst(SmallVector<AstNodeRef>& out, const Ast& ast) const;

    static void collectChildren(const SmallVector<AstNodeRef>& out, const Ast& ast)
    {
        SWC_UNUSED(out);
        SWC_UNUSED(ast);
    }

    static Result semaPreDecl(const Sema& sema)
    {
        SWC_UNUSED(sema);
        return Result::Continue;
    }

    static Result semaPreDeclChild(const Sema& sema, const AstNodeRef& childRef)
    {
        SWC_UNUSED(sema);
        SWC_UNUSED(childRef);
        return Result::Continue;
    }

    static Result semaPostDeclChild(const Sema& sema, const AstNodeRef& childRef)
    {
        SWC_UNUSED(sema);
        SWC_UNUSED(childRef);
        return Result::Continue;
    }

    static Result semaPostDecl(const Sema& sema)
    {
        SWC_UNUSED(sema);
        return Result::Continue;
    }

    static Result semaPreNode(const Sema& sema)
    {
        SWC_UNUSED(sema);
        return Result::Continue;
    }

    static Result semaPreNodeChild(const Sema& sema, const AstNodeRef& childRef)
    {
        SWC_UNUSED(sema);
        SWC_UNUSED(childRef);
        return Result::Continue;
    }

    static Result semaPostNodeChild(const Sema& sema, const AstNodeRef& childRef)
    {
        SWC_UNUSED(sema);
        SWC_UNUSED(childRef);
        return Result::Continue;
    }

    static Result semaPostNode(const Sema& sema)
    {
        SWC_UNUSED(sema);
        return Result::Continue;
    }

    static void semaErrorCleanup(const Sema& sema, AstNodeRef nodeRef)
    {
        SWC_UNUSED(sema);
        SWC_UNUSED(nodeRef);
    }

    static AstNodeRef semaClone(const Sema& sema, const CloneContext& cloneContext)
    {
        SWC_UNUSED(sema);
        SWC_UNUSED(cloneContext);
        return AstNodeRef::invalid();
    }

    static Result codeGenPreNode(const CodeGen& codeGen)
    {
        SWC_UNUSED(codeGen);
        return Result::Continue;
    }

    static Result codeGenPreNodeChild(const CodeGen& codeGen, const AstNodeRef& childRef)
    {
        SWC_UNUSED(codeGen);
        SWC_UNUSED(childRef);
        return Result::Continue;
    }

    static Result codeGenPostNodeChild(const CodeGen& codeGen, const AstNodeRef& childRef)
    {
        SWC_UNUSED(codeGen);
        SWC_UNUSED(childRef);
        return Result::Continue;
    }

    static Result codeGenPostNode(const CodeGen& codeGen)
    {
        SWC_UNUSED(codeGen);
        return Result::Continue;
    }

    static constexpr uint64_t payloadBitsMask() { return 0xFFFFull; }
    static constexpr uint32_t payloadRefShift() { return 16; }
    static constexpr uint64_t payloadRefMask() { return 0xFFFFFFFFull << payloadRefShift(); }

    static constexpr uint64_t makePayloadState(uint16_t bits, uint32_t ref)
    {
        return static_cast<uint64_t>(bits) | (static_cast<uint64_t>(ref) << payloadRefShift());
    }

    static constexpr uint16_t payloadBitsFromState(uint64_t state)
    {
        return static_cast<uint16_t>(state & payloadBitsMask());
    }

    static constexpr uint32_t payloadRefFromState(uint64_t state)
    {
        return static_cast<uint32_t>((state & payloadRefMask()) >> payloadRefShift());
    }

    uint64_t payloadState(std::memory_order mo = std::memory_order_acquire) const
    {
        return payloadStorage_.load(mo);
    }

    void storePayloadState(uint64_t state, std::memory_order mo = std::memory_order_release)
    {
        payloadStorage_.store(state, mo);
    }

    void clearPayload()
    {
        payloadStorage_.store(0, std::memory_order_release);
    }

    uint16_t payloadBits() const { return payloadBitsFromState(payloadState()); }
    uint32_t payloadRef() const { return payloadRefFromState(payloadState()); }

    ParserFlags parserFlags() const { return parserFlags_; }

    AstNodeId id() const { return id_; }
    void      setId(AstNodeId id) { id_ = id; }
    bool      is(AstNodeId id) const { return id_ == id; }
    bool      isNot(AstNodeId id) const { return id_ != id; }

    const SourceView&    srcView(const TaskContext& ctx) const;
    const Ast*           sourceAst(const TaskContext& ctx) const;
    SourceCodeRange      codeRange(const TaskContext& ctx) const;
    SourceCodeRange      codeRangeWithChildren(const TaskContext& ctx, const Ast& ast) const;
    const SourceCodeRef& codeRef() const { return codeRef_; }
    void                 setCodeRef(const SourceCodeRef& codeRef) { codeRef_ = codeRef; }
    SourceViewRef        srcViewRef() const { return codeRef_.srcViewRef; }
    TokenRef             tokRef() const { return codeRef_.tokRef; }
    TokenRef             tokRefEnd(const Ast& ast) const;
    AstNodeRef           nodeRef(const Ast& ast) const;

    template<typename T>
    T& cast()
    {
        SWC_ASSERT(is(T::ID));
        return *reinterpret_cast<T*>(this);
    }

    template<typename T>
    const T& cast() const
    {
        SWC_ASSERT(is(T::ID));
        return *reinterpret_cast<const T*>(this);
    }

    template<typename T>
    T* safeCast()
    {
        if (!is(T::ID))
            return nullptr;
        return reinterpret_cast<T*>(this);
    }

    template<typename T>
    const T* safeCast() const
    {
        if (!is(T::ID))
            return nullptr;
        return reinterpret_cast<const T*>(this);
    }

#if SWC_HAS_REF_DEBUG_INFO
    AstNodeRef dbgMyRef;
#endif

protected:
    std::atomic<uint64_t> payloadStorage_{0};
    AstNodeId             id_ = AstNodeId::Invalid;
    ParserFlags           parserFlags_{};
    SourceCodeRef         codeRef_;
};

template<AstNodeId I, typename E = void>
struct AstNodeT : AstNode
{
    static constexpr AstNodeId ID = I;
    using FlagsE                  = E;
    using FlagsType               = std::conditional_t<std::is_void_v<E>, uint8_t, EnumFlags<E>>;

    AstNodeT() :
        AstNode(I, SourceCodeRef::invalid())
    {
    }

    explicit AstNodeT(const SourceCodeRef& codeRef) :
        AstNode(I, codeRef)
    {
    }

    FlagsType& flags()
    {
        if constexpr (!std::is_void_v<E>)
            return *reinterpret_cast<FlagsType*>(&parserFlags_);
        else
            return parserFlags_;
    }

    const FlagsType& flags() const
    {
        if constexpr (!std::is_void_v<E>)
            return *reinterpret_cast<const FlagsType*>(&parserFlags_);
        else
            return parserFlags_;
    }

    template<typename T = E>
    bool hasFlag(T flag) const
    {
        if constexpr (!std::is_void_v<E>)
            return flags().has(flag);
        return false;
    }

    template<typename T = E>
    void addFlag(T flag)
    {
        if constexpr (!std::is_void_v<E>)
            flags().add(flag);
    }
};

SWC_END_NAMESPACE();
