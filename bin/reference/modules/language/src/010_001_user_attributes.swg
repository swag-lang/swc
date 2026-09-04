#global private

/**
# User Attributes

Attributes in Swag let you annotate code elements (functions, structs, etc.)
with metadata. These annotations, defined with the 'attr' keyword, can power
code generation and reflection. By attaching attributes, you
enrich code with extra information usable at compile time and at runtime.
*/

using Swag

attr AttributeA()

// Simple attribute without parameters

/**
# Attributes with Parameters

Attributes can accept parameters, similar to functions. Parameters let you
customize how the attribute configures the annotated element.
*/
attr AttributeB(x, y: s32, z: string)

// Attribute with multiple parameters

/**
# Attributes with Default Values

Attributes may define default parameter values. When applied, omitted arguments
fall back to their defaults.
*/
attr AttributeBA(x: s32, y: string = "string")

// Attribute with a defaulted parameter

/**
# Restricting Attribute Usage

Use the 'AttrUsage' specifier to control where an attribute may be applied
(e.g., function-only, struct-only). The compiler rejects the attribute on any
other declaration kind. An attribute that declares no 'AttrUsage' is accepted
everywhere.
*/
#[AttrUsage(AttributeUsage.Function)]
attr AttributeC()

// Restricted to function usage

/**
# Scopes and Broadcasting

An attribute written on a block applies to every declaration the block
contains, and each of those declarations is checked against 'AttrUsage'
separately. A declaration the attribute does not accept simply does not receive
it, so one block can carry an attribute meant for only some of its members.

'AttributeUsage.Scope' marks an attribute that acts on the lexical scope itself
instead of on a declaration; 'Swag.Safety', 'Swag.Sanity', 'Swag.Warning', and
'Swag.Optimize' are the predefined ones.
*/

/**
# Applying Attributes

Apply attributes with the syntax '#[attribute, attribute...]' placed immediately
before the code element. Multiple attributes are comma-separated.
*/
#[AttributeA, AttributeB(0, 0, "string")]
func function1()
{
    // Function annotated with multiple attributes
}

/**
# Multiple Usages

An attribute can target several element kinds by combining 'AttrUsage' flags
with a bitwise OR. This enables reuse across contexts (e.g., functions, structs).
*/
#[AttrUsage(AttributeUsage.Function | AttributeUsage.Struct)]
attr AttributeD(x: s32)

// Applicable to both functions and structs

#[AttributeD(6)]
func function2()
{
    // Function annotated with a multi-usage attribute
}

#[AttributeD(150)]
struct struct1
{
    // Struct annotated with the same attribute
}

/**
# Retrieving Attributes at Runtime

You can inspect attributes via type reflection at runtime. This enables behavior
that adapts based on which attributes are present and how they are configured.
*/

#test
{
    let type = cast(const *Swag.TypeInfoFunc) #typeof(function2)     // Reflect the function type
    Swag.assert(type.attributes.count == 1)                          // Exactly one attribute on 'function2'
}
