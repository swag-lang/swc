#pragma once
SWC_BEGIN_NAMESPACE()

enum class DeclContextKind
{
    Invalid = -1,
    Module,
    Namespace,
};

class DeclContext
{
    DeclContextKind kind_ = DeclContextKind::Invalid;

public:
    explicit DeclContext(DeclContextKind kind) :
        kind_(kind)
    {
    }

    DeclContextKind kind() const { return kind_; }
};

SWC_END_NAMESPACE()
