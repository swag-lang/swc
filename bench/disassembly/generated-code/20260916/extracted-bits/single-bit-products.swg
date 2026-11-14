#global public

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func bit0Product64(a,b:u64)->u64 => ((a >> 0) & 1) * b

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func bit1Product64(a,b:u64)->u64 => ((a >> 1) & 1) * b

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func bit7Product64(a,b:u64)->u64 => ((a >> 7) & 1) * b

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func bit8Product64(a,b:u64)->u64 => ((a >> 8) & 1) * b

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func bit15Product64(a,b:u64)->u64 => ((a >> 15) & 1) * b

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func bit16Product64(a,b:u64)->u64 => ((a >> 16) & 1) * b

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func bit17Product64(a,b:u64)->u64 => ((a >> 17) & 1) * b

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func bit31Product64(a,b:u64)->u64 => ((a >> 31) & 1) * b

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func bit32Product64(a,b:u64)->u64 => ((a >> 32) & 1) * b

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func bit40Product64(a,b:u64)->u64 => ((a >> 40) & 1) * b

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func bit63Product64(a,b:u64)->u64 => ((a >> 63) & 1) * b

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func bit7Product32(a,b:u32)->u32 => ((a >> 7) & 1) * b

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func bit15Product32(a,b:u32)->u32 => ((a >> 15) & 1) * b

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func bit31Product32(a,b:u32)->u32 => ((a >> 31) & 1) * b
