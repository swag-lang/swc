#pragma once

SWC_BEGIN_NAMESPACE()

using Ref                 = uint32_t;
constexpr Ref INVALID_REF = std::numeric_limits<Ref>::max();

using AstNodeRef    = Ref;
using AstPayloadRef = Ref;
using FileRef       = Ref;
using TokenRef      = Ref;
using SpanRef       = Ref;
using JobClientId   = Ref;

SWC_END_NAMESPACE()
