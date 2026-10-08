// An arrow: a line whose caps point the way.
#[Serialization.TypeKey("swag.capture.form.arrow")]
struct FormArrow
{
    using line: FormLine
}

impl IForm for FormArrow {}
