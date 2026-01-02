#pragma once
#include "Core/SmallVector.h"
#include "Core/Store.h"
#include "Lexer/SourceView.h"
#include "Parser/AstNodeId.h"

SWC_BEGIN_NAMESPACE()
class TypeInfo;
class Sema;
class Ast;
class SourceFile;
class TaskContext;
class ConstantValue;
struct SourceCodeLocation;

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

struct AstNode;
using AstNodeRef = StrongRef<AstNode>;

struct AstNode
{
    // ReSharper disable once CppPossiblyUninitializedMember
    explicit AstNode(AstNodeId nodeId, SourceViewRef srcViewRef, TokenRef tokRef) :
        id_(nodeId),
        srcViewRef_(srcViewRef),
        tokRef_(tokRef)
    {
    }

    using ParserFlags = uint8_t;

    template<typename T>
    EnumFlags<T> parserFlags() const
    {
        return static_cast<EnumFlags<T>>(parserFlags_);
    }

    void clearFlags()
    {
        parserFlags_ = 0;
        semaBits_    = 0;
    }

    template<typename T>
    void addParserFlag(T val)
    {
        if constexpr (std::is_enum_v<T>)
            parserFlags_ |= static_cast<std::underlying_type_t<T>>(val);
        else
            parserFlags_ |= val.flags;
    }

    template<typename T>
    bool hasParserFlag(T val) const
    {
        if constexpr (std::is_enum_v<T>)
            return parserFlags_ & static_cast<std::underlying_type_t<T>>(val);
        else
            return parserFlags_ & val.flags;
    }

    static void collectChildren(SmallVector<AstNodeRef>&, const Ast&) {}
    static void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast, SpanRef spanRef);
    static void collectChildren(SmallVector<AstNodeRef>& out, std::initializer_list<AstNodeRef> nodes);

    static AstStepResult semaPreDecl(Sema&) { return AstStepResult::Continue; }
    static AstStepResult semaPreDeclChild(Sema&, AstNodeRef&) { return AstStepResult::Continue; }
    static AstStepResult semaPostDecl(Sema&) { return AstStepResult::Continue; }
    static void      semaEnterNode(Sema&) {}
    static AstStepResult semaPreNode(Sema&) { return AstStepResult::Continue; }
    static AstStepResult semaPreNodeChild(Sema&, AstNodeRef&) { return AstStepResult::Continue; }
    static AstStepResult semaPostNode(Sema&) { return AstStepResult::Continue; }

    uint8_t&       semaBits() { return semaBits_; }
    const uint8_t& semaBits() const { return semaBits_; }
    uint32_t       semaRef() const { return semaRef_; }
    void           setSemaRef(uint32_t val) { semaRef_ = val; }

    AstNodeId id() const { return id_; }
    void      setId(AstNodeId id) { id_ = id; }
    bool      is(AstNodeId id) const { return id_ == id; }
    bool      isNot(AstNodeId id) const { return id_ != id; }

    SourceCodeLocation location(const TaskContext& ctx) const;
    SourceCodeLocation locationWithChildren(const TaskContext& ctx, const Ast& ast) const;
    const SourceView&  srcView(const TaskContext& ctx) const;
    SourceViewRef      srcViewRef() const { return srcViewRef_; }
    TokenRef           tokRef() const { return tokRef_; }
    TokenRef           tokRefEnd(const Ast& ast) const;

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

private:
    AstNodeId     id_ = AstNodeId::Invalid;
    ParserFlags   parserFlags_{};
    uint8_t       semaBits_   = 0;
    SourceViewRef srcViewRef_ = SourceViewRef::invalid();
    TokenRef      tokRef_     = TokenRef::invalid();
    uint32_t      semaRef_    = 0;
};

template<AstNodeId I>
struct AstNodeT : AstNode
{
    static constexpr auto ID = I;
    explicit AstNodeT(SourceViewRef srcViewRef, TokenRef tokRef) :
        AstNode(I, srcViewRef, tokRef)
    {
    }
};

SWC_END_NAMESPACE()
