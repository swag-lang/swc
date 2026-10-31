//! TagBin v1 framing, following core/serialization/{read,write}/tagbin.swg.
//! Field identities come from the persisted v1 schema, not Rust type names.
use serde::{Deserialize, Serialize};
use std::io::{Read, Write};

pub const U8: u32 = 0x66531939;
pub const I32: u32 = 0x66536728;
pub const U32: u32 = 0x66536757;
pub const U64: u32 = 0x66536f7f;
pub const F32: u32 = 0x096f8769;
pub const BOOL: u32 = 0xb2379d29;
pub const STRING: u32 = 0xf5cd808e;
pub const BYTES: u32 = 0x396bafab;
pub const STRINGS: u32 = 0x25c9154b;
pub const FORMS: u32 = 0x221130dd;
pub const GUID: u32 = 0xed4ee11e;
const ROOT: u32 = 0xc0de0000;
const FAT: u32 = ROOT + 1;
const SEQUENCE: u32 = ROOT + 2;
const VERSION: u32 = ROOT + 3;
const RAW: u32 = ROOT + 4;
const UNRAW: u32 = ROOT + 5;
const SHAPES: u32 = ROOT + 6;
const MAX_BYTES: usize = 256 * 1024 * 1024;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Field {
    pub key: String,
    pub kind: u32,
    pub value: Value,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum Value {
    Bytes(Vec<u8>),
    Raw(Vec<u8>),
    Object {
        version: u32,
        fields: Vec<Field>,
    },
    Sequence {
        count: usize,
        raw: Option<Vec<u8>>,
        items: Vec<Value>,
    },
    Interface {
        key: String,
        value: Box<Value>,
    },
}

pub fn object(version: u32, fields: Vec<Field>) -> Value {
    Value::Object { version, fields }
}
pub fn field(key: &str, kind: u32, value: Value) -> Field {
    Field {
        key: key.into(),
        kind,
        value,
    }
}
pub fn integer(n: u32) -> Value {
    Value::Bytes(n.to_le_bytes().to_vec())
}
pub fn long(n: u64) -> Value {
    Value::Bytes(n.to_le_bytes().to_vec())
}
pub fn float(n: f32) -> Value {
    Value::Bytes(n.to_le_bytes().to_vec())
}
pub fn byte(n: u8) -> Value {
    Value::Bytes(vec![n])
}
pub fn text(s: &str) -> Value {
    let mut b = vec![];
    varint(&mut b, s.len());
    b.extend_from_slice(s.as_bytes());
    Value::Bytes(b)
}
pub fn sequence(items: Vec<Value>) -> Value {
    Value::Sequence {
        count: items.len(),
        raw: None,
        items,
    }
}
pub fn raw_sequence(count: usize, bytes: Vec<u8>) -> Value {
    Value::Sequence {
        count,
        raw: Some(bytes),
        items: vec![],
    }
}

impl Value {
    pub fn get(&self, key: &str) -> Option<&Value> {
        if let Self::Object { fields, .. } = self {
            fields.iter().find(|f| f.key == key).map(|f| &f.value)
        } else {
            None
        }
    }
    pub fn set(&mut self, key: &str, kind: u32, value: Value) {
        if let Self::Object { fields, .. } = self {
            if let Some(f) = fields.iter_mut().find(|f| f.key == key) {
                f.value = value;
            } else {
                fields.push(field(key, kind, value));
            }
        }
    }
    pub fn bytes(&self) -> Option<&[u8]> {
        match self {
            Self::Bytes(b) | Self::Raw(b) => Some(b),
            Self::Sequence { raw: Some(b), .. } => Some(b),
            _ => None,
        }
    }
    pub fn number(&self) -> Option<u64> {
        let bytes = self.bytes()?;
        match bytes.len() {
            1 => Some(bytes[0] as u64),
            4 => Some(u32::from_le_bytes(bytes.try_into().ok()?) as u64),
            8 => Some(u64::from_le_bytes(bytes.try_into().ok()?)),
            _ => None,
        }
    }
    pub fn real(&self) -> Option<f32> {
        Some(f32::from_le_bytes(self.bytes()?.try_into().ok()?))
    }
    pub fn string(&self) -> Option<String> {
        let mut r = Cursor::new(self.bytes()?);
        r.string().ok()
    }
    pub fn items(&self) -> &[Value] {
        if let Self::Sequence { items, .. } = self {
            items
        } else {
            &[]
        }
    }
    pub fn n(&self, key: &str, fallback: u64) -> u64 {
        self.get(key).and_then(Value::number).unwrap_or(fallback)
    }
    pub fn f(&self, key: &str, fallback: f32) -> f32 {
        self.get(key)
            .and_then(Value::real)
            .filter(|n| n.is_finite())
            .unwrap_or(fallback)
    }
    pub fn s(&self, key: &str) -> String {
        self.get(key).and_then(Value::string).unwrap_or_default()
    }
}

struct Cursor<'a> {
    bytes: &'a [u8],
    pos: usize,
}
impl<'a> Cursor<'a> {
    fn new(bytes: &'a [u8]) -> Self {
        Self { bytes, pos: 0 }
    }
    fn take(&mut self, count: usize) -> Result<&'a [u8], String> {
        let end = self
            .pos
            .checked_add(count)
            .ok_or("TagBin offset overflow.")?;
        let b = self
            .bytes
            .get(self.pos..end)
            .ok_or("Truncated TagBin value.")?;
        self.pos = end;
        Ok(b)
    }
    fn u32(&mut self) -> Result<u32, String> {
        Ok(u32::from_le_bytes(self.take(4)?.try_into().unwrap()))
    }
    fn u64(&mut self) -> Result<u64, String> {
        Ok(u64::from_le_bytes(self.take(8)?.try_into().unwrap()))
    }
    fn varint(&mut self) -> Result<usize, String> {
        let mut value = 0u64;
        for shift in (0..64).step_by(7) {
            let b = self.take(1)?[0];
            if shift == 63 && b > 1 {
                return Err("TagBin integer overflow.".into());
            }
            value |= ((b & 127) as u64) << shift;
            if b < 128 {
                return usize::try_from(value).map_err(|e| e.to_string());
            }
        }
        Err("TagBin integer overflow.".into())
    }
    fn string(&mut self) -> Result<String, String> {
        let count = self.varint()?;
        String::from_utf8(self.take(count)?.to_vec()).map_err(|e| e.to_string())
    }
}

pub fn inflate(bytes: &[u8], size: usize) -> Result<Vec<u8>, String> {
    if size > MAX_BYTES {
        return Err("Decoded SCC payload exceeds the size limit.".into());
    }
    let mut decoder = flate2::read::ZlibDecoder::new(bytes).take(size as u64 + 1);
    let mut output = Vec::with_capacity(size.min(1024 * 1024));
    decoder
        .read_to_end(&mut output)
        .map_err(|e| e.to_string())?;
    if output.len() != size {
        return Err("Decoded SCC payload length does not match.".into());
    }
    Ok(output)
}

pub fn deflate(bytes: &[u8]) -> Result<Vec<u8>, String> {
    let mut encoder = flate2::write::ZlibEncoder::new(Vec::new(), flate2::Compression::fast());
    encoder.write_all(bytes).map_err(|e| e.to_string())?;
    encoder.finish().map_err(|e| e.to_string())
}

type Shape = Vec<(String, u32, u8)>;
fn read_value(
    r: &mut Cursor<'_>,
    kind: u32,
    shapes: &[Shape],
    depth: usize,
) -> Result<Value, String> {
    if depth > 64 {
        return Err("TagBin nesting exceeds the limit.".into());
    }
    let scalar_size = match kind {
        U8 | BOOL => 1,
        I32 | U32 | F32 => 4,
        U64 => 8,
        _ => 0,
    };
    if scalar_size != 0 {
        return Ok(Value::Bytes(r.take(scalar_size)?.to_vec()));
    }
    if kind == STRING {
        let start = r.pos;
        let count = r.varint()?;
        r.take(count)?;
        return Ok(Value::Bytes(r.bytes[start..r.pos].to_vec()));
    }
    let signature = r.u32()?;
    match signature {
        RAW => {
            let size = usize::try_from(r.u64()?).map_err(|e| e.to_string())?;
            Ok(Value::Raw(r.take(size)?.to_vec()))
        }
        VERSION | FAT => {
            let version = if signature == VERSION { r.u32()? } else { 0 };
            if signature == VERSION && r.u32()? != FAT {
                return Err("Invalid TagBin object header.".into());
            }
            let id = r.u32()? as usize;
            let fat = usize::try_from(r.u64()?).map_err(|e| e.to_string())?;
            if id == u32::MAX as usize {
                let count = usize::try_from(r.u64()?).map_err(|e| e.to_string())?;
                if count > 100_000 || fat < r.pos || fat >= r.bytes.len() {
                    return Err("Invalid TagBin dynamic section.".into());
                }
                let mut index = Cursor {
                    bytes: r.bytes,
                    pos: fat,
                };
                if index.u32()? != FAT {
                    return Err("Invalid TagBin dynamic index.".into());
                }
                let mut entries = Vec::with_capacity(count);
                for _ in 0..count {
                    let key = index.string()?;
                    let position = usize::try_from(index.u64()?).map_err(|e| e.to_string())?;
                    if position < r.pos || position >= fat {
                        return Err("Invalid TagBin dynamic field offset.".into());
                    }
                    entries.push((position, key));
                }
                entries.sort_by_key(|e| e.0);
                let mut fields = vec![];
                for (i, (position, key)) in entries.iter().enumerate() {
                    let end = entries.get(i + 1).map(|e| e.0).unwrap_or(fat);
                    let mut child = Cursor {
                        bytes: &r.bytes[..end],
                        pos: *position,
                    };
                    if child.string()? != *key {
                        return Err("TagBin dynamic field key does not match.".into());
                    }
                    let kind = child.u32()?;
                    let flags = child.take(1)?[0];
                    if flags & !3 != 0 || flags & 1 == 0 {
                        return Err("Unsupported TagBin dynamic field flags.".into());
                    }
                    let value = if flags & 2 != 0 {
                        let size = usize::try_from(child.u64()?).map_err(|e| e.to_string())?;
                        let stored = usize::try_from(child.u64()?).map_err(|e| e.to_string())?;
                        let data = child.take(stored)?;
                        let decoded = if size == stored {
                            data.to_vec()
                        } else {
                            inflate(data, size)?
                        };
                        read_value(&mut Cursor::new(&decoded), kind, shapes, depth + 1)?
                    } else {
                        read_value(&mut child, kind, shapes, depth + 1)?
                    };
                    fields.push(field(key, kind, value));
                }
                r.pos = index.pos;
                return Ok(object(version, fields));
            }
            let start = r.pos;
            let shape = shapes.get(id).ok_or("Unsupported TagBin shape.")?;
            if fat < start
                || fat
                    .checked_add(shape.len() * 4)
                    .is_none_or(|end| end > r.bytes.len())
            {
                return Err("Invalid TagBin field offsets.".into());
            }
            let mut offsets = Cursor {
                bytes: r.bytes,
                pos: fat,
            };
            let mut positions = Vec::with_capacity(shape.len() + 1);
            for _ in shape {
                positions.push(
                    start
                        .checked_add(offsets.u32()? as usize)
                        .ok_or("TagBin field overflow.")?,
                );
            }
            positions.push(fat);
            if positions.windows(2).any(|w| w[0] > w[1] || w[1] > fat) {
                return Err("Invalid TagBin field order.".into());
            }
            let mut fields = Vec::with_capacity(shape.len());
            for (i, (key, kind, flags)) in shape.iter().enumerate() {
                let mut child = Cursor {
                    bytes: &r.bytes[..positions[i + 1]],
                    pos: positions[i],
                };
                let value = if flags & 1 != 0 {
                    let size = usize::try_from(child.u64()?).map_err(|e| e.to_string())?;
                    let stored = usize::try_from(child.u64()?).map_err(|e| e.to_string())?;
                    let b = child.take(stored)?;
                    let decoded = if size == stored {
                        b.to_vec()
                    } else {
                        inflate(b, size)?
                    };
                    read_value(&mut Cursor::new(&decoded), *kind, shapes, depth + 1)?
                } else {
                    read_value(&mut child, *kind, shapes, depth + 1)?
                };
                fields.push(field(key, *kind, value));
            }
            r.pos = fat + shape.len() * 4;
            Ok(object(version, fields))
        }
        SEQUENCE => {
            let count = r.varint()?;
            if count > MAX_BYTES || count > r.bytes.len() {
                return Err("TagBin sequence exceeds the limit.".into());
            }
            let raw = r.u32()?;
            if raw == RAW {
                let size = r.varint()?;
                return Ok(raw_sequence(count, r.take(size)?.to_vec()));
            }
            if raw != UNRAW {
                return Err("Invalid TagBin sequence.".into());
            }
            let mut items = Vec::with_capacity(count.min(65536));
            for _ in 0..count {
                if kind == FORMS {
                    let size = usize::try_from(r.u64()?).map_err(|e| e.to_string())?;
                    let end = r
                        .pos
                        .checked_add(size)
                        .filter(|end| *end <= r.bytes.len())
                        .ok_or("Truncated interface object.")?;
                    let key = r.string()?;
                    let value = read_value(r, 0, shapes, depth + 1)?;
                    if r.pos != end {
                        return Err("Interface object length does not match.".into());
                    }
                    items.push(Value::Interface {
                        key,
                        value: Box::new(value),
                    });
                } else {
                    items.push(read_value(
                        r,
                        if kind == STRINGS { STRING } else { 0 },
                        shapes,
                        depth + 1,
                    )?);
                }
            }
            Ok(sequence(items))
        }
        _ => Err(format!("Unsupported TagBin value {signature:08x}.")),
    }
}

pub fn decode(bytes: &[u8], expected_schema: &str) -> Result<Value, String> {
    let mut r = Cursor::new(bytes);
    if r.u32()? != ROOT || r.u32()? != 0xfafafafc {
        return Err("Unsupported TagBin version.".into());
    }
    if r.string()? != expected_schema {
        return Err("Unexpected TagBin document schema.".into());
    }
    let flags = r.u32()?;
    let shape_offset = usize::try_from(r.u64()?).map_err(|e| e.to_string())?;
    if flags & !1 != 0 {
        return Err("Unsupported TagBin stream flags.".into());
    }
    let body = if flags & 1 != 0 {
        let size = usize::try_from(r.u64()?).map_err(|e| e.to_string())?;
        let stored = usize::try_from(r.u64()?).map_err(|e| e.to_string())?;
        let b = r.take(stored)?;
        if size == stored {
            b.to_vec()
        } else {
            inflate(b, size)?
        }
    } else {
        r.bytes[r.pos..].to_vec()
    };
    let mut r = Cursor {
        bytes: &body,
        pos: shape_offset,
    };
    if r.u32()? != SHAPES {
        return Err("Invalid TagBin shape directory.".into());
    }
    let count = r.varint()?;
    if count > 100_000 {
        return Err("Too many TagBin shapes.".into());
    }
    let mut shapes = Vec::with_capacity(count);
    for _ in 0..count {
        let count = r.varint()?;
        if count > 100_000 {
            return Err("Too many TagBin fields.".into());
        }
        let mut fields = Vec::with_capacity(count);
        for _ in 0..count {
            fields.push((r.string()?, r.u32()?, r.take(1)?[0]));
        }
        shapes.push(fields);
    }
    read_value(&mut Cursor::new(&body), 0, &shapes, 0)
}

fn varint(bytes: &mut Vec<u8>, mut value: usize) {
    while value >= 128 {
        bytes.push((value as u8 & 127) | 128);
        value >>= 7;
    }
    bytes.push(value as u8);
}
fn word(bytes: &mut Vec<u8>, value: u32) {
    bytes.extend_from_slice(&value.to_le_bytes());
}
fn wide(bytes: &mut Vec<u8>, value: u64) {
    bytes.extend_from_slice(&value.to_le_bytes());
}
fn string(bytes: &mut Vec<u8>, value: &str) {
    varint(bytes, value.len());
    bytes.extend_from_slice(value.as_bytes());
}

fn write_value(value: &Value, bytes: &mut Vec<u8>, shapes: &mut Vec<Shape>) {
    match value {
        Value::Bytes(data) => bytes.extend_from_slice(data),
        Value::Raw(data) => {
            word(bytes, RAW);
            wide(bytes, data.len() as u64);
            bytes.extend_from_slice(data);
        }
        Value::Object { version, fields } => {
            let shape: Shape = fields.iter().map(|f| (f.key.clone(), f.kind, 0)).collect();
            let id = shapes.iter().position(|s| *s == shape).unwrap_or_else(|| {
                shapes.push(shape);
                shapes.len() - 1
            });
            word(bytes, VERSION);
            word(bytes, *version);
            word(bytes, FAT);
            word(bytes, id as u32);
            let patch = bytes.len();
            wide(bytes, 0);
            let start = bytes.len();
            let mut offsets = vec![];
            for field in fields {
                offsets.push((bytes.len() - start) as u32);
                write_value(&field.value, bytes, shapes);
            }
            let fat = bytes.len() as u64;
            bytes[patch..patch + 8].copy_from_slice(&fat.to_le_bytes());
            for offset in offsets {
                word(bytes, offset);
            }
        }
        Value::Sequence { count, raw, items } => {
            word(bytes, SEQUENCE);
            varint(bytes, *count);
            if let Some(data) = raw {
                word(bytes, RAW);
                varint(bytes, data.len());
                bytes.extend_from_slice(data);
            } else {
                word(bytes, UNRAW);
                for item in items {
                    write_value(item, bytes, shapes);
                }
            }
        }
        Value::Interface { key, value } => {
            let patch = bytes.len();
            wide(bytes, 0);
            let start = bytes.len();
            string(bytes, key);
            write_value(value, bytes, shapes);
            let size = (bytes.len() - start) as u64;
            bytes[patch..patch + 8].copy_from_slice(&size.to_le_bytes());
        }
    }
}

pub fn encode(schema: &str, value: &Value) -> Vec<u8> {
    let mut body = vec![];
    let mut shapes = vec![];
    write_value(value, &mut body, &mut shapes);
    let offset = body.len();
    word(&mut body, SHAPES);
    varint(&mut body, shapes.len());
    for shape in shapes {
        varint(&mut body, shape.len());
        for (key, kind, flags) in shape {
            string(&mut body, &key);
            word(&mut body, kind);
            body.push(flags);
        }
    }
    let mut output = vec![];
    word(&mut output, ROOT);
    word(&mut output, 0xfafafafc);
    string(&mut output, schema);
    word(&mut output, 0);
    wide(&mut output, offset as u64);
    output.extend_from_slice(&body);
    output
}
