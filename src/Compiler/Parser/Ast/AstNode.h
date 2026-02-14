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
        payloadBits_    = 0;
    }

    static void collectChildren(SmallVector<AstNodeRef>&, const Ast&) {}
    static void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast, SpanRef spanRef);
    static void collectChildren(SmallVector<AstNodeRef>& out, std::initializer_list<AstNodeRef> nodes);
    void        collectChildrenFromAst(SmallVector<AstNodeRef>& out, const Ast& ast) const;

    static Result     semaPreDecl(Sema&) { return Result::Continue; }
    static Result     semaPreDeclChild(Sema&, AstNodeRef&) { return Result::Continue; }
    static Result     semaPostDeclChild(Sema&, AstNodeRef&) { return Result::Continue; }
    static Result     semaPostDecl(Sema&) { return Result::Continue; }
    static Result     semaPreNode(Sema&) { return Result::Continue; }
    static Result     semaPreNodeChild(Sema&, AstNodeRef&) { return Result::Continue; }
    static Result     semaPostNodeChild(Sema&, AstNodeRef&) { return Result::Continue; }
    static Result     semaPostNode(Sema&) { return Result::Continue; }
    static void       semaErrorCleanup(Sema&, AstNodeRef) {}
    static AstNodeRef semaClone(Sema&, const CloneContext&) { return AstNodeRef::invalid(); }
    static Result     codeGenPreNode(CodeGen&) { return Result::Continue; }
    static Result     codeGenPreNodeChild(CodeGen&, AstNodeRef&) { return Result::Continue; }
    static Result     codeGenPostNodeChild(CodeGen&, AstNodeRef&) { return Result::Continue; }
    static Result     codeGenPostNode(CodeGen&) { return Result::Continue; }

    uint16_t&       payloadBits() { return payloadBits_; }
    const uint16_t& payloadBits() const { return payloadBits_; }
    uint32_t        payloadRef() const { return payloadRef_; }
    void            setPayloadRef(uint32_t val) { payloadRef_ = val; }

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
    T* cast()
    {
        SWC_ASSERT(is(T::ID));
        return reinterpret_cast<T*>(this);
    }

    template<typename T>
    const T* cast() const
    {
        SWC_ASSERT(is(T::ID));
        return reinterpret_cast<const T*>(this);
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
    uint16_t      payloadBits_ = 0;
    AstNodeId     id_       = AstNodeId::Invalid;
    ParserFlags   parserFlags_{};
    SourceCodeRef codeRef_;
    uint32_t      payloadRef_ = 0;
};

template<AstNodeId I, typename E = void>
struct AstNodeT : AstNode
{
    static constexpr auto ID = I;
    using FlagsE             = E;
    using FlagsType          = std::conditional_t<std::is_void_v<E>, uint8_t, EnumFlags<E>>;

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
