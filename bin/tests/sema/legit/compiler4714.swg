#global fileprivate // swc-option sema-only
#global skip
enum AA { A, B }

const FirstLine:  [?] AA = [.A, .B]
const FirstLine1: const [..] AA = [.A, .B]
const FirstLine2  = [AA.A, .B]
