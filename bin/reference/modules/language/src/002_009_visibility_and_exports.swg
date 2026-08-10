#global private

/**
# Visibility

Top-level declarations use three visibility levels:

| Modifier   | Visible from the same file | Other files in the module | Importing modules |
| ---------- | -------------------------- | ------------------------- | ----------------- |
| 'private'  | yes                        | no                        | no                |
| 'internal' | yes                        | yes                       | no                |
| 'public'   | yes                        | yes                       | yes               |

'internal' is the default, for a top-level declaration and for an aggregate member
alike. Use 'public' deliberately for the supported module API and 'private' for
file-local implementation details.
*/

private const VisibilityFileLocal = 10
internal const VisibilityModuleLocal = 20

#test
{
    @assert(VisibilityFileLocal + VisibilityModuleLocal == 30)
}

/**
# Applying Visibility to a Group or File

An access block applies one modifier to several declarations:

```swag
public
{
    struct Request
    {
        public id: u64
    }

    func submit(request: Request)
}
```

'#global' changes the default for the rest of one source file. This reference
starts files with '#global private' so examples cannot leak into a generated
module API:

```swag
#global private
```

Both forms set the default for the declarations they cover, and neither reaches
inside an aggregate: a member belongs to its type rather than to a file or a
block, so it states its own access in the aggregate body. That is why 'Request'
above says 'public' twice.

Visibility is independent of namespaces. A symbol can be public and qualified,
or private and placed in a namespace for organization.

# Member Access

The three levels and their default are the same on a member. What changes is who the owner
is. A declaration belongs to its file, so 'private' at the top level means "this file". A
**member belongs to its type**, so on a field the same word grants the type: the file that
declares the aggregate, and every file that declares an 'impl' of it, inside the module
that declares the type. One rule, one reading: 'private' grants the owner, 'internal'
grants the module, 'public' grants everyone, and 'internal' is what a member gets when it
says nothing — a type publishes its state as deliberately as it publishes its functions.

Granting those files, rather than the enclosing 'impl' alone, is what makes the rule hold
in practice. A type spreads its 'impl' over platform or concern files, and reaches its own
state from a mixin or an inlined body without the access depending on where that body
expands.

'readonly' is the one modifier a top-level declaration has no use for. It is not a fourth
level: it rides on the level in effect, keeps the reads that level grants, and restricts
the writes to the declaring type.

| Modifier            | Read from        | Written from     |
| ------------------- | ---------------- | ---------------- |
| 'public'            | anywhere         | anywhere         |
| 'public readonly'   | anywhere         | declaring type   |
| 'internal'          | declaring module | declaring module |
| 'readonly'          | declaring module | declaring type   |
| 'private'           | declaring type   | declaring type   |

Written alone, 'readonly' rides on the level already in effect, which is 'internal' unless
an enclosing access block says otherwise. It always comes last, and 'private readonly' is
rejected: 'private' already withholds every write from outside the type.
*/

struct Counter
{
    public readonly
    count: s32
    private
    step:  s32 = 2
}

impl Counter
{
    // The declaring type reaches and writes every level.
    mtd bump()
    {
        .count += .step
    }
}

#test
{
    var c: Counter
    c.bump()
    c.bump()

    // 'public readonly' reads from anywhere; only its own type writes it.
    @assert(c.count == 4)
}

/**
'readonly' restricts writing through the field's name; it does not freeze the whole
value. Assigning the aggregate, copying it, and dropping it stay ordinary operations.

Naming a field in a struct literal writes it, so the write rule applies there too: a
literal can only initialize the fields the site could assign.

An anonymous aggregate — a returned tuple, an inline union — carries no declaration a
modifier could be written on, so its members are public. What holds the anonymous value
is what decides who reaches them.

Reflection reports the declared access through 'Swag.TypeValueFlags', so a generic
walker such as a serializer or a property editor can leave implementation state alone
instead of persisting it.

# Exporting a File's API

'#global export' is a fourth form. It sets the same access as '#global public', and
additionally marks the file as one whose declarations belong to the generated module
API. Only the file's first '#global' directive is read for that marking, so it belongs
on the very first line. The standard modules open their public source files with it:

```swag
#global export
```

Use '#global public' when a file is public inside the workspace, and '#global export'
when its declarations are the module's published surface.
*/
