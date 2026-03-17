#global fileprivate // swc-option sema-only
#global skip
struct ParseOptions {}

func parse(options = ParseOptions{}) {}

#test
{
    parse()
}
