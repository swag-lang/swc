#[Serialization.TypeKey("swag.capture.form.arrow")]
struct FormArrow
{
    using line: FormLine
}

impl IForm for FormArrow {}
