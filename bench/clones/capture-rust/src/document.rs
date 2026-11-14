use eframe::egui::{Pos2, Rect, Vec2, pos2, vec2};
use image::RgbaImage;
use serde::{Deserialize, Serialize};
use std::{collections::BTreeSet, path::Path, sync::Arc};

pub const MAX_SIZE: u32 = 4096;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum Tool {
    #[default]
    Select,
    Shape,
    Polygon,
    Arrow,
    Line,
    Text,
    Callout,
    Draw,
    Highlight,
    Step,
    Image,
    PixelSelection,
}

impl Tool {
    pub const ALL: [Self; 12] = [
        Self::Select,
        Self::Shape,
        Self::Polygon,
        Self::Arrow,
        Self::Line,
        Self::Text,
        Self::Callout,
        Self::Draw,
        Self::Highlight,
        Self::Step,
        Self::Image,
        Self::PixelSelection,
    ];

    pub fn name(self) -> &'static str {
        match self {
            Self::Select => "Select",
            Self::Shape => "Shape",
            Self::Polygon => "Polygon",
            Self::Arrow => "Arrow",
            Self::Line => "Line",
            Self::Text => "Text",
            Self::Callout => "Callout",
            Self::Draw => "Draw",
            Self::Highlight => "Highlight",
            Self::Step => "Step",
            Self::Image => "Image",
            Self::PixelSelection => "Pixel Selection",
        }
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum ShapeKind {
    #[default]
    Ellipse,
    Rectangle,
    Rounded,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum ImageKind {
    #[default]
    Image,
    Blur,
    Pixelate,
    Zoom,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Style {
    pub fill: [u8; 4],
    pub outline: [u8; 4],
    pub thickness: f32,
    pub opacity: f32,
    pub rotation: f32,
    pub radius: f32,
    pub font_size: f32,
    pub shadow: bool,
    pub bold: bool,
    pub italic: bool,
    pub filled: bool,
    pub shape: ShapeKind,
    pub image_kind: ImageKind,
    pub strength: u32,
    pub arrow_size: f32,
    pub font_name: String,
    pub align_h: u32,
    pub align_v: u32,
    pub line_spacing: f32,
    pub bold_size: f32,
    pub scale: f32,
    pub join: u32,
    pub dash: u32,
    pub bezier: bool,
    pub begin_cap: u32,
    pub end_cap: u32,
    pub start_size: f32,
    pub line_outline: f32,
    pub line_outline_color: [u8; 4],
    pub numbering: u32,
    pub text_color: [u8; 4],
}

impl Default for Style {
    fn default() -> Self {
        Self {
            fill: [232, 8, 8, 255],
            outline: [255; 4],
            thickness: 5.,
            opacity: 100.,
            rotation: 0.,
            radius: 10.,
            font_size: 48.,
            shadow: true,
            bold: false,
            italic: false,
            filled: true,
            shape: ShapeKind::Ellipse,
            image_kind: ImageKind::Image,
            strength: 50,
            arrow_size: 3.,
            font_name: "Inter".into(),
            align_h: 2,
            align_v: 2,
            line_spacing: 14.,
            bold_size: 0.,
            scale: 0.,
            join: 2,
            dash: 0,
            bezier: false,
            begin_cap: 2,
            end_cap: 2,
            start_size: 4.,
            line_outline: 0.,
            line_outline_color: [0, 0, 0, 255],
            numbering: 0,
            text_color: [255; 4],
        }
    }
}

impl Style {
    pub fn apply_changed(&mut self, before: &Self, after: &Self) {
        macro_rules! update { ($($field:ident),*) => { $(if before.$field != after.$field { self.$field = after.$field.clone(); })* }; }
        update!(
            fill,
            outline,
            thickness,
            opacity,
            rotation,
            radius,
            font_size,
            shadow,
            bold,
            italic,
            filled,
            shape,
            image_kind,
            strength,
            arrow_size,
            font_name,
            align_h,
            align_v,
            line_spacing,
            bold_size,
            scale,
            join,
            dash,
            bezier,
            begin_cap,
            end_cap,
            start_size,
            line_outline,
            line_outline_color,
            numbering,
            text_color
        );
    }
    pub fn for_tool(tool: Tool) -> Self {
        let mut style = Self::default();
        match tool {
            Tool::Shape | Tool::Polygon => {
                style.fill = [0; 4];
                style.outline = [232, 8, 8, 255];
                style.thickness = 10.;
                style.shape = ShapeKind::Rounded;
                style.filled = false;
            }
            Tool::Arrow => {
                style.outline = [232, 8, 8, 255];
                style.end_cap = 4;
                style.begin_cap = 0;
                style.arrow_size = 4.;
            }
            Tool::Highlight => {
                style.fill = [253, 223, 27, 255];
                style.outline = style.fill;
                style.thickness = 24.;
                style.opacity = 40.;
                style.shadow = false;
            }
            Tool::Callout => {
                style.font_size = 40.;
                style.radius = 16.;
            }
            Tool::Line | Tool::Draw => style.outline = [232, 8, 8, 255],
            _ => {}
        }
        style
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Form {
    pub id: u64,
    pub tool: Tool,
    pub bounds: [f32; 4],
    pub points: Vec<[f32; 2]>,
    pub text: String,
    pub step: u32,
    pub style: Style,
    pub groups: Vec<u64>,
    pub frozen: bool,
    pub control: [f32; 2],
    pub tail: [f32; 2],
    #[serde(default)]
    pub source_fields: Option<Arc<crate::tagbin::Value>>,
    #[serde(skip)]
    pub image: Option<Arc<RgbaImage>>,
}

impl Form {
    pub fn new(id: u64, tool: Tool, start: Pos2, style: Style, step: u32) -> Self {
        Self {
            id,
            tool,
            bounds: [start.x, start.y, 1., 1.],
            points: vec![[start.x, start.y]],
            text: String::new(),
            step,
            style,
            groups: Vec::new(),
            frozen: false,
            control: [start.x + 10., start.y + 10.],
            tail: [start.x + 10., start.y + 45.],
            source_fields: None,
            image: None,
        }
    }

    pub fn rect(&self) -> Rect {
        Rect::from_min_size(
            pos2(self.bounds[0], self.bounds[1]),
            vec2(self.bounds[2], self.bounds[3]),
        )
    }

    pub fn set_rect(&mut self, rect: Rect) {
        let old = self.rect();
        for p in [&mut self.control, &mut self.tail] {
            p[0] = rect.min.x + (p[0] - old.min.x) * rect.width() / old.width().max(1.);
            p[1] = rect.min.y + (p[1] - old.min.y) * rect.height() / old.height().max(1.);
        }
        for p in &mut self.points {
            p[0] = rect.min.x + (p[0] - old.min.x) * rect.width() / old.width().max(1.);
            p[1] = rect.min.y + (p[1] - old.min.y) * rect.height() / old.height().max(1.);
        }
        self.bounds = [
            rect.min.x,
            rect.min.y,
            rect.width().max(1.),
            rect.height().max(1.),
        ];
    }

    pub fn translate(&mut self, delta: Vec2) {
        self.bounds[0] += delta.x;
        self.bounds[1] += delta.y;
        for p in [&mut self.control, &mut self.tail] {
            p[0] += delta.x;
            p[1] += delta.y;
        }
        for p in &mut self.points {
            p[0] += delta.x;
            p[1] += delta.y;
        }
    }

    pub fn draw_to(&mut self, start: Pos2, mut end: Pos2, constrain: bool) {
        if constrain {
            let d = end - start;
            if matches!(self.tool, Tool::Arrow | Tool::Line) {
                let angle =
                    (d.angle() / std::f32::consts::FRAC_PI_4).round() * std::f32::consts::FRAC_PI_4;
                end = start + Vec2::angled(angle) * d.length();
            } else {
                let size = d.x.abs().max(d.y.abs());
                end = start + vec2(size * d.x.signum(), size * d.y.signum());
            }
        }
        match self.tool {
            Tool::Draw | Tool::Highlight => {
                if self
                    .points
                    .last()
                    .is_none_or(|p| pos2(p[0], p[1]).distance(end) > 1.)
                {
                    self.points.push([end.x, end.y]);
                }
                let r = Rect::from_points(
                    &self
                        .points
                        .iter()
                        .map(|p| pos2(p[0], p[1]))
                        .collect::<Vec<_>>(),
                );
                self.bounds = [r.min.x, r.min.y, r.width().max(1.), r.height().max(1.)];
            }
            _ => {
                self.points = vec![[start.x, start.y], [end.x, end.y]];
                let r = Rect::from_two_pos(start, end);
                self.bounds = [r.min.x, r.min.y, r.width().max(1.), r.height().max(1.)];
                self.control = [r.center().x, r.center().y];
                self.tail = [r.left() + r.width() * 0.2, r.bottom() + r.height() * 0.3];
            }
        }
    }

    pub fn path_points(&self) -> Vec<Pos2> {
        if self.style.bezier
            && matches!(self.tool, Tool::Arrow | Tool::Line)
            && self.points.len() >= 2
        {
            let a = pos2(self.points[0][0], self.points[0][1]);
            let b = pos2(self.points[1][0], self.points[1][1]);
            let c = pos2(self.control[0], self.control[1]);
            return (0..=48)
                .map(|i| {
                    let t = i as f32 / 48.;
                    (a.to_vec2() * (1. - t).powi(2)
                        + c.to_vec2() * (2. * t * (1. - t))
                        + b.to_vec2() * t * t)
                        .to_pos2()
                })
                .collect();
        }
        self.points.iter().map(|p| pos2(p[0], p[1])).collect()
    }

    pub fn hit(&self, point: Pos2, tolerance: f32) -> bool {
        let center = self.rect().center();
        let v = point - center;
        let (s, c) = (-self.style.rotation.to_radians()).sin_cos();
        let point = center + vec2(v.x * c - v.y * s, v.x * s + v.y * c);
        if matches!(
            self.tool,
            Tool::Arrow | Tool::Line | Tool::Draw | Tool::Highlight
        ) {
            return crate::stroke::hit(self, point, tolerance);
        }
        if !self
            .rect()
            .expand(tolerance + self.style.thickness)
            .contains(point)
        {
            return false;
        }
        if self.tool == Tool::Shape && self.style.shape == ShapeKind::Ellipse {
            let r = self.rect();
            let p = (point - r.center()) / (r.size() / 2. + Vec2::splat(tolerance));
            return p.length_sq() <= 1.;
        }
        true
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Document {
    pub width: u32,
    pub height: u32,
    pub forms: Vec<Form>,
    pub next_id: u64,
    pub next_group: u64,
    pub next_step: u32,
    pub title: String,
    pub tags: String,
    pub favorite: bool,
    pub rating: u8,
    pub source: String,
    #[serde(default)]
    pub background_position: [f32; 2],
    #[serde(default)]
    pub source_fields: Option<Arc<crate::tagbin::Value>>,
    #[serde(skip)]
    pub background: Arc<RgbaImage>,
    #[serde(skip)]
    pub original: Arc<RgbaImage>,
}

impl Document {
    pub fn blank(width: u32, height: u32) -> Self {
        Self::from_image(
            RgbaImage::from_pixel(
                width.clamp(16, MAX_SIZE),
                height.clamp(16, MAX_SIZE),
                image::Rgba([255; 4]),
            ),
            "Blank Canvas",
        )
    }

    pub fn from_image(image: RgbaImage, source: &str) -> Self {
        let (width, height) = image.dimensions();
        let image = Arc::new(image);
        Self {
            width,
            height,
            forms: vec![],
            next_id: 1,
            next_group: 1,
            next_step: 1,
            title: String::new(),
            tags: String::new(),
            favorite: false,
            rating: 0,
            source: source.to_owned(),
            background_position: [0., 0.],
            source_fields: None,
            background: image.clone(),
            original: image,
        }
    }

    pub fn rect(&self) -> Rect {
        Rect::from_min_size(Pos2::ZERO, vec2(self.width as f32, self.height as f32))
    }

    pub fn background_pixels(&self) -> Arc<RgbaImage> {
        if self.background_position == [0., 0.]
            && self.background.dimensions() == (self.width, self.height)
        {
            return self.background.clone();
        }
        let mut pixels = RgbaImage::new(self.width, self.height);
        image::imageops::overlay(
            &mut pixels,
            &*self.background,
            self.background_position[0].round() as i64,
            self.background_position[1].round() as i64,
        );
        Arc::new(pixels)
    }

    pub fn create(&mut self, tool: Tool, point: Pos2, style: Style) -> u64 {
        let id = self.next_id;
        self.next_id += 1;
        self.forms
            .push(Form::new(id, tool, point, style, self.next_step));
        if tool == Tool::Step {
            self.next_step += 1;
        }
        id
    }

    pub fn selection_rect(&self, selection: &BTreeSet<u64>) -> Option<Rect> {
        self.forms
            .iter()
            .filter(|f| selection.contains(&f.id))
            .map(Form::rect)
            .reduce(|a, b| a.union(b))
    }

    pub fn select_at(&self, point: Pos2, tolerance: f32) -> BTreeSet<u64> {
        let mut selection = BTreeSet::new();
        if let Some(hit) = self
            .forms
            .iter()
            .rev()
            .find(|f| !f.frozen && f.hit(point, tolerance))
        {
            selection.insert(hit.id);
            if let Some(group) = hit.groups.first() {
                selection.extend(
                    self.forms
                        .iter()
                        .filter(|f| f.groups.first() == Some(group))
                        .map(|f| f.id),
                );
            }
        }
        selection
    }

    pub fn group(&mut self, selection: &BTreeSet<u64>) {
        if selection.len() < 2 {
            return;
        }
        let group = self.next_group;
        self.next_group += 1;
        for form in &mut self.forms {
            if selection.contains(&form.id) {
                form.groups.insert(0, group);
            }
        }
    }

    pub fn ungroup(&mut self, selection: &BTreeSet<u64>) {
        for form in &mut self.forms {
            if selection.contains(&form.id) && !form.groups.is_empty() {
                form.groups.remove(0);
            }
        }
    }

    pub fn paste(&mut self, forms: &[Form], offset: Vec2) -> BTreeSet<u64> {
        let mut selection = BTreeSet::new();
        let mut groups = std::collections::BTreeMap::new();
        for form in forms {
            let mut form = form.clone();
            form.id = self.next_id;
            self.next_id += 1;
            form.translate(offset);
            for group in &mut form.groups {
                *group = *groups.entry(*group).or_insert_with(|| {
                    let n = self.next_group;
                    self.next_group += 1;
                    n
                });
            }
            selection.insert(form.id);
            self.forms.push(form);
        }
        selection
    }

    pub fn align(&mut self, selection: &BTreeSet<u64>, axis: usize, factor: f32) {
        let Some(bounds) = self.selection_rect(selection) else {
            return;
        };
        for form in &mut self.forms {
            if !selection.contains(&form.id) || form.frozen {
                continue;
            }
            let r = form.rect();
            let delta = if axis == 0 {
                vec2(
                    bounds.min.x + bounds.width() * factor - r.min.x - r.width() * factor,
                    0.,
                )
            } else {
                vec2(
                    0.,
                    bounds.min.y + bounds.height() * factor - r.min.y - r.height() * factor,
                )
            };
            form.translate(delta);
        }
    }

    pub fn arrange(&mut self, selection: &BTreeSet<u64>, direction: i32, extreme: bool) {
        if extreme {
            self.forms.sort_by_key(|f| {
                if direction > 0 {
                    selection.contains(&f.id)
                } else {
                    !selection.contains(&f.id)
                }
            });
        } else if direction > 0 {
            for i in (0..self.forms.len().saturating_sub(1)).rev() {
                if selection.contains(&self.forms[i].id)
                    && !selection.contains(&self.forms[i + 1].id)
                {
                    self.forms.swap(i, i + 1);
                }
            }
        } else {
            for i in 1..self.forms.len() {
                if selection.contains(&self.forms[i].id)
                    && !selection.contains(&self.forms[i - 1].id)
                {
                    self.forms.swap(i, i - 1);
                }
            }
        }
    }

    pub fn crop(&mut self, rect: Rect) {
        let rect = rect.intersect(self.rect());
        let x = rect.min.x.max(0.).floor() as u32;
        let y = rect.min.y.max(0.).floor() as u32;
        let w = (rect.width().round() as u32).min(self.width - x);
        let h = (rect.height().round() as u32).min(self.height - y);
        if w == 0 || h == 0 {
            return;
        }
        self.background_position[0] -= x as f32;
        self.background_position[1] -= y as f32;
        self.width = w;
        self.height = h;
        for form in &mut self.forms {
            form.translate(vec2(-(x as f32), -(y as f32)));
        }
    }

    pub fn resize(&mut self, width: u32, height: u32) {
        let width = width.clamp(16, MAX_SIZE);
        let height = height.clamp(16, MAX_SIZE);
        let scale = vec2(
            width as f32 / self.width as f32,
            height as f32 / self.height as f32,
        );
        self.background = Arc::new(image::imageops::resize(
            &*self.background_pixels(),
            width,
            height,
            image::imageops::FilterType::Lanczos3,
        ));
        self.background_position = [0., 0.];
        for form in &mut self.forms {
            let r = form.rect();
            form.set_rect(Rect::from_min_size(
                pos2(r.min.x * scale.x, r.min.y * scale.y),
                r.size() * scale,
            ));
        }
        self.width = width;
        self.height = height;
    }

    pub fn read_image(path: &Path) -> Result<Self, String> {
        let reader = image::ImageReader::open(path)
            .map_err(|e| e.to_string())?
            .with_guessed_format()
            .map_err(|e| e.to_string())?;
        let image = reader.decode().map_err(|e| e.to_string())?.to_rgba8();
        if image.width() > MAX_SIZE || image.height() > MAX_SIZE {
            return Err(format!("Image dimensions exceed {MAX_SIZE} pixels."));
        }
        let mut result = Self::from_image(image, "Image File");
        result.title = path
            .file_stem()
            .unwrap_or_default()
            .to_string_lossy()
            .into_owned();
        Ok(result)
    }
}

pub struct History {
    undo: Vec<Document>,
    redo: Vec<Document>,
    pending: Option<Document>,
}

impl Default for History {
    fn default() -> Self {
        Self {
            undo: vec![],
            redo: vec![],
            pending: None,
        }
    }
}

impl History {
    pub fn begin(&mut self, doc: &Document) {
        if self.pending.is_none() {
            self.pending = Some(doc.clone());
        }
    }
    pub fn commit(&mut self) {
        if let Some(doc) = self.pending.take() {
            self.undo.push(doc);
            if self.undo.len() > 100 {
                self.undo.remove(0);
            }
            self.redo.clear();
        }
    }
    pub fn cancel(&mut self, doc: &mut Document) {
        if let Some(previous) = self.pending.take() {
            *doc = previous;
        }
    }
    pub fn undo(&mut self, doc: &mut Document) {
        self.commit();
        if let Some(previous) = self.undo.pop() {
            self.redo.push(std::mem::replace(doc, previous));
        }
    }
    pub fn redo(&mut self, doc: &mut Document) {
        if let Some(next) = self.redo.pop() {
            self.undo.push(std::mem::replace(doc, next));
        }
    }
    pub fn can_undo(&self) -> bool {
        !self.undo.is_empty()
    }
    pub fn can_redo(&self) -> bool {
        !self.redo.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn nested_groups_and_paste_do_not_alias_original_groups() {
        let mut doc = Document::blank(640, 480);
        let a = doc.create(Tool::Shape, pos2(10., 10.), Style::default());
        let b = doc.create(Tool::Text, pos2(100., 100.), Style::default());
        let selection = BTreeSet::from([a, b]);
        doc.group(&selection);
        doc.group(&selection);
        let copied = doc.forms.clone();
        doc.paste(&copied, vec2(20., 20.));
        assert_ne!(doc.forms[0].groups[0], doc.forms[2].groups[0]);
        assert_eq!(doc.forms[2].groups, doc.forms[3].groups);
        doc.ungroup(&selection);
        assert_eq!(doc.forms[0].groups.len(), 1);
        assert_eq!(doc.forms[2].groups.len(), 2);
    }
    #[test]
    fn whole_drag_is_one_undo_and_new_edit_invalidates_redo() {
        let mut doc = Document::blank(640, 480);
        let mut history = History::default();
        history.begin(&doc);
        doc.create(Tool::Arrow, pos2(10., 10.), Style::default());
        for i in 1..100 {
            doc.forms[0].draw_to(pos2(10., 10.), pos2(i as f32, 100.), false);
        }
        history.commit();
        history.undo(&mut doc);
        assert!(doc.forms.is_empty());
        history.redo(&mut doc);
        assert_eq!(doc.forms[0].points[1], [99., 100.]);
        history.undo(&mut doc);
        history.begin(&doc);
        doc.create(Tool::Step, pos2(2., 2.), Style::default());
        history.commit();
        assert!(!history.can_redo());
    }
    #[test]
    fn crop_moves_forms_and_preserves_original_pixels() {
        let mut doc = Document::blank(200, 100);
        doc.create(Tool::Shape, pos2(50., 50.), Style::default());
        doc.crop(Rect::from_min_size(pos2(20., 30.), vec2(80., 40.)));
        assert_eq!((doc.width, doc.height), (80, 40));
        assert_eq!(&doc.forms[0].bounds[..2], &[30., 20.]);
        assert_eq!(doc.original.dimensions(), (200, 100));
    }
}
