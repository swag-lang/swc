#pragma once
#include "Core/SmallVector.h"
#include "Parser/AstNodeId.h"

SWC_BEGIN_NAMESPACE()
class Ast;

class SourceFile;

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
};
using AstModifierFlags = EnumFlags<AstModifierFlagsE>;

struct AstNode
{
    AstNodeId id = AstNodeId::Invalid;

    // ReSharper disable once CppPossiblyUninitializedMember
    explicit AstNode(AstNodeId nodeId) :
        id(nodeId)
    {
    }

    using ParserFlags = uint8_t;
    using SemaFlags   = uint8_t;

    template<typename T>
    EnumFlags<T> parserFlags() const
    {
        return static_cast<EnumFlags<T>>(parserFlags_);
    }

    template<typename T>
    EnumFlags<T> semaFlags() const
    {
        return static_cast<EnumFlags<T>>(semaFlags_);
    }

    void clearFlags()
    {
        parserFlags_ = 0;
        semaFlags_   = 0;
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
    void addSemaFlag(T val)
    {
        if constexpr (std::is_enum_v<T>)
            semaFlags_ |= static_cast<std::underlying_type_t<T>>(val);
        else
            semaFlags_ |= val.flags;
    }

    static void       collectChildren(SmallVector<AstNodeRef>&, const Ast*) {}
    static void       collectChildren(SmallVector<AstNodeRef>& out, const Ast* ast, SpanRef spanRef);
    static void       collectChildren(SmallVector<AstNodeRef>& out, std::initializer_list<AstNodeRef> nodes);
    static AstNodeRef semaPreChild(AstNodeRef childRef) { return childRef; }

private:
    ParserFlags parserFlags_;
    SemaFlags   semaFlags_;
};

template<AstNodeId I>
struct AstNodeT : AstNode
{
    static constexpr auto ID = I;
    AstNodeT() :
        AstNode(I)
    {
    }
};

template<typename T>
T* castAst(AstNode* node)
{
    SWC_ASSERT(node);
    SWC_ASSERT(node->id == T::ID);
    return reinterpret_cast<T*>(node);
}

template<typename T>
const T* castAst(const AstNode* node)
{
    SWC_ASSERT(node);
    SWC_ASSERT(node->id == T::ID);
    return reinterpret_cast<const T*>(node);
}

SWC_END_NAMESPACE()
