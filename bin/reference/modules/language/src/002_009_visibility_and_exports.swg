#global private

/**
# Visibility

Top-level declarations use three visibility levels:

| Modifier   | Visible from the same file | Other files in the module | Importing modules |
| ---------- | -------------------------- | ------------------------- | ----------------- |
| 'private'  | yes                        | no                        | no                |
| 'internal' | yes                        | yes                       | no                |
| 'public'   | yes                        | yes                       | yes               |

'internal' is the default. Use 'public' deliberately for the supported module
API and 'private' for file-local implementation details.
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
        id: u64
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

Visibility is independent of namespaces. A symbol can be public and qualified,
or private and placed in a namespace for organization.
*/
