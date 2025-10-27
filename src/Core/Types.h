#pragma once

using Ref                 = uint32_t;
constexpr Ref INVALID_REF = std::numeric_limits<Ref>::max();

using AstNodeRef    = Ref;
using AstPayloadRef = Ref;
using FileRef       = Ref;
using TokenRef      = Ref;
using JobClientId   = Ref;
