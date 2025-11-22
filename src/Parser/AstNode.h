#pragma once
#include "Core/SmallVector.h"
#include "Parser/AstNodeId.h"
#include "Parser/AstVisit.h"
#include "Sema/ConstantValue.h"

SWC_BEGIN_NAMESPACE()
class SemaJob;
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
        semaFlags_.clear();
    }

    template<typename T>
    void addParserFlag(T val)
    {
        if constexpr (std::is_enum_v<T>)
            parserFlags_ |= static_cast<std::underlying_type_t<T>>(val);
        else
            parserFlags_ |= val.flags;
    }

    static void               collectChildren(SmallVector<AstNodeRef>&, const Ast&) {}
    static void               collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast, SpanRef spanRef);
    static void               collectChildren(SmallVector<AstNodeRef>& out, std::initializer_list<AstNodeRef> nodes);
    static AstVisitStepResult semaPreNode(SemaJob&) { return AstVisitStepResult::Continue; }
    static AstVisitStepResult semaPostNode(SemaJob&) { return AstVisitStepResult::Continue; }
    static AstVisitStepResult semaPreChild(SemaJob&, AstNodeRef&) { return AstVisitStepResult::Continue; }

    enum class SemaFlagE : uint8_t
    {
        IsConst = 1 << 0,
        RefMask = IsConst,
    };
    using SemaFlags = EnumFlags<SemaFlagE>;

    void      addSemaFlag(SemaFlagE val) { semaFlags_.add(val); }
    bool      hasSemaFlag(SemaFlagE val) const { return semaFlags_.has(val); }
    SemaFlags semaFlags() const { return semaFlags_; }

    bool                 isConstant() const { return hasSemaFlag(SemaFlagE::IsConst); }
    void                 setConstant(ConstantRef ref);
    const ConstantValue& getConstant(const TaskContext& ctx) const;

    AstNodeId     id() const { return id_; }
    void          setId(AstNodeId id) { id_ = id; }
    bool          is(AstNodeId id) const { return id_ == id; }
    bool          isNot(AstNodeId id) const { return id_ != id; }
    SourceViewRef srcViewRef() const { return srcViewRef_; }
    TokenRef      tokRef() const { return tokRef_; }
    TokenRef      tokRefEnd(const Ast& ast) const;

private:
    AstNodeId                 id_ = AstNodeId::Invalid;
    ParserFlags               parserFlags_{};
    SemaFlags                 semaFlags_{};
    SourceViewRef             srcViewRef_ = SourceViewRef::invalid();
    TokenRef                  tokRef_     = TokenRef::invalid();
    std::variant<ConstantRef> sema_{};
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

template<typename T>
T* castAst(AstNode* node)
{
    SWC_ASSERT(node);
    SWC_ASSERT(node->is(T::ID));
    return reinterpret_cast<T*>(node);
}

template<typename T>
const T* castAst(const AstNode* node)
{
    SWC_ASSERT(node);
    SWC_ASSERT(node->is(T::ID));
    return reinterpret_cast<const T*>(node);
}

SWC_END_NAMESPACE()
