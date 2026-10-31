use crate::document::Style;
use crate::{
    commands::Command,
    document::*,
    native,
    renderer::{self, Renderer},
    storage::{self, Settings},
    theme::{self, Palette, Strings},
};
use eframe::egui::{self, *};
use std::{
    collections::BTreeSet,
    path::PathBuf,
    sync::Arc,
    time::{Duration, Instant},
};

enum Drag {
    Create {
        id: u64,
        start: Pos2,
    },
    Move {
        start: Pos2,
        forms: Vec<Form>,
    },
    Handle {
        id: u64,
        original: Form,
        start: Pos2,
        handle: crate::gizmo::Handle,
    },
    Marquee {
        start: Pos2,
        end: Pos2,
    },
    Pan {
        start: Vec2,
    },
}

#[derive(Clone, Copy, PartialEq)]
enum Dialog {
    New,
    Resize,
    About,
    Options,
    Close,
}

struct CaptureRequest {
    mode: Command,
    result: std::sync::mpsc::Receiver<Result<native::Captured, String>>,
    window: native::WindowToken,
    restore: native::ScreenRect,
    scale: f32,
}
struct Overlay {
    image: Arc<image::RgbaImage>,
    desktop: native::ScreenRect,
    start: Option<Pos2>,
    restore: native::ScreenRect,
    window: native::WindowToken,
    scale: f32,
}

struct LibraryEntry {
    path: PathBuf,
    title: String,
    texture: Option<TextureHandle>,
    favorite: bool,
    rating: u8,
    metadata: Option<crate::library::Metadata>,
    pending: bool,
    error: Option<String>,
    last_visible: usize,
}

pub struct CaptureApp {
    pub doc: Document,
    pub renderer: Renderer,
    pub zoom: f32,
    pub pan: Vec2,
    pub tool: Tool,
    pub selection: BTreeSet<u64>,
    pub settings: Settings,
    pub root: PathBuf,
    pub dirty: bool,
    pub frame_times: Vec<f64>,
    pub drag_frame_times: Vec<f64>,
    pub frames: usize,
    pub smoke_frames: Option<usize>,
    pub benchmark_frames: Option<usize>,
    pub report: Option<PathBuf>,
    pub screenshot: Option<PathBuf>,
    strings: Strings,
    palette: Palette,
    dark: bool,
    style: Style,
    tool_styles: Vec<Style>,
    pub show_caption: bool,
    history: History,
    clipboard: Vec<Form>,
    drag: Option<Drag>,
    inspector: bool,
    lens: bool,
    lens_query: String,
    lens_focus: bool,
    lens_index: usize,
    dialog: Option<Dialog>,
    dialog_size: [u32; 2],
    editing_text: Option<u64>,
    path: Option<PathBuf>,
    message: Option<(String, Instant)>,
    error: Option<String>,
    library: bool,
    library_entries: Vec<LibraryEntry>,
    library_query: String,
    library_favorites: bool,
    library_loader: Option<crate::library::Loader>,
    library_indexed: bool,
    library_selected: Option<usize>,
    library_preview_count: usize,
    library_visible_images: usize,
    library_last_visible: usize,
    pub library_smoke: bool,
    library_smoke_stage: u8,
    library_smoke_frames: usize,
    library_screenshot_requested: bool,
    pub capture_smoke: bool,
    capture_smoke_stage: u8,
    capture_smoke_ticks: usize,
    capture_checks: Vec<String>,
    capture_request: Option<CaptureRequest>,
    overlay: Option<Overlay>,
    last_area: Option<native::ScreenRect>,
    queued: Vec<Command>,
    fit: bool,
    allow_close: bool,
    started: Instant,
    first_frame_ms: Option<f64>,
    fonts_pending: bool,
}

impl CaptureApp {
    pub fn new(ctx: &Context, root: PathBuf) -> Self {
        let settings = Settings::load(&root);
        let strings = Strings::new(settings.french);
        ctx.set_fonts(theme::fonts_for(
            settings
                .presets
                .iter()
                .flatten()
                .map(|s| s.font_name.as_str()),
        ));
        let dark = settings.theme != "Light";
        let palette = Palette::new(dark);
        palette.apply(ctx, dark);
        let tool = match settings.edit_mode {
            1 => Tool::Arrow,
            2 => Tool::Line,
            3 => Tool::Polygon,
            4 => Tool::Text,
            6 => Tool::Draw,
            7 => Tool::Highlight,
            8 => Tool::Select,
            9 => Tool::Step,
            10 => Tool::Image,
            11 => Tool::PixelSelection,
            12 => Tool::Callout,
            _ => Tool::Shape,
        };
        let tool_styles: Vec<_> = Tool::ALL
            .iter()
            .enumerate()
            .map(|(i, t)| {
                settings
                    .presets
                    .get(i)
                    .and_then(|p| p.first())
                    .cloned()
                    .unwrap_or_else(|| Style::for_tool(*t))
            })
            .collect();
        let inspector = !settings.inspector_folded;
        Self {
            doc: Document::blank(960, 540),
            renderer: Renderer::default(),
            zoom: 1.,
            pan: Vec2::ZERO,
            tool,
            selection: BTreeSet::new(),
            settings,
            root,
            dirty: false,
            frame_times: vec![],
            drag_frame_times: vec![],
            frames: 0,
            smoke_frames: None,
            benchmark_frames: None,
            report: None,
            screenshot: None,
            strings,
            palette,
            dark,
            style: tool_styles[tool as usize].clone(),
            tool_styles,
            show_caption: true,
            history: History::default(),
            clipboard: vec![],
            drag: None,
            inspector,
            lens: false,
            lens_query: String::new(),
            lens_focus: false,
            lens_index: 0,
            dialog: None,
            dialog_size: [960, 540],
            editing_text: None,
            path: None,
            message: None,
            error: None,
            library: false,
            library_entries: vec![],
            library_query: String::new(),
            library_favorites: false,
            library_loader: None,
            library_indexed: false,
            library_selected: None,
            library_preview_count: 0,
            library_visible_images: 0,
            library_last_visible: 0,
            library_smoke: false,
            library_smoke_stage: 0,
            library_smoke_frames: 0,
            library_screenshot_requested: false,
            capture_smoke: false,
            capture_smoke_stage: 0,
            capture_smoke_ticks: 0,
            capture_checks: vec![],
            capture_request: None,
            overlay: None,
            last_area: None,
            queued: vec![],
            fit: true,
            allow_close: false,
            started: Instant::now(),
            first_frame_ms: None,
            fonts_pending: false,
        }
    }

    fn tr(&self, label: &str) -> String {
        self.strings.text(label)
    }
    fn toast(&mut self, message: impl Into<String>) {
        self.message = Some((message.into(), Instant::now()));
    }

    pub fn load(&mut self, path: PathBuf) {
        let result = if path
            .extension()
            .is_some_and(|e| e.eq_ignore_ascii_case("scc"))
        {
            storage::load(&path)
        } else {
            Document::read_image(&path)
        };
        match result {
            Ok(doc) => {
                self.replace(doc);
                if path
                    .extension()
                    .is_some_and(|e| e.eq_ignore_ascii_case("scc"))
                {
                    self.path = Some(path);
                }
            }
            Err(error) => self.error = Some(error),
        }
    }

    pub fn load_recent(&mut self) {
        if let Some((path, doc)) = storage::newest_capture(&self.settings.library) {
            self.replace(doc);
            self.settings.last_capture = Some(path.clone());
            self.path = Some(path);
        }
    }

    fn replace(&mut self, doc: Document) {
        self.doc = doc;
        self.fonts_pending = true;
        self.selection.clear();
        self.history = History::default();
        self.renderer.clear();
        self.dirty = false;
        self.path = None;
        self.pan = Vec2::ZERO;
        self.fit = true;
        self.library = false;
        self.editing_text = None;
    }

    fn mutate(&mut self, action: impl FnOnce(&mut Document, &BTreeSet<u64>)) {
        self.history.begin(&self.doc);
        action(&mut self.doc, &self.selection);
        self.history.commit();
        self.dirty = true;
    }

    fn save(&mut self, choose: bool) -> bool {
        let path = if choose || self.path.is_none() {
            rfd::FileDialog::new()
                .set_title(self.tr("Save Capture…"))
                .add_filter("Swag Capture", &["scc"])
                .set_directory(&self.settings.library)
                .set_file_name("capture.scc")
                .save_file()
        } else {
            self.path.clone()
        };
        let Some(path) = path else {
            return false;
        };
        match storage::save(&path, &self.doc) {
            Ok(()) => {
                self.path = Some(path);
                self.dirty = false;
                self.toast(self.tr("Saved"));
                true
            }
            Err(error) => {
                self.error = Some(error);
                false
            }
        }
    }

    fn archive(&mut self) -> bool {
        if !self.dirty {
            return true;
        }
        let path = self.path.clone().unwrap_or_else(|| {
            let stamp = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis();
            self.settings.library.join(format!("capture-{stamp}.scc"))
        });
        match storage::save(&path, &self.doc) {
            Ok(()) => {
                self.path = Some(path);
                self.dirty = false;
                true
            }
            Err(error) => {
                self.error = Some(error);
                false
            }
        }
    }

    fn enabled(&self, command: Command) -> bool {
        use Command::*;
        match command {
            OpenSelected => {
                self.library
                    && self
                        .library_selected
                        .is_some_and(|i| i < self.library_entries.len())
            }
            Undo => self.history.can_undo(),
            Redo => self.history.can_redo(),
            Paste => !self.clipboard.is_empty(),
            Copy | Cut | Duplicate | Delete | Group | Ungroup | Freeze | Front | Back | Forward
            | Backward | AlignLeft | AlignCenter | AlignRight | AlignTop | AlignMiddle
            | AlignBottom | Crop => !self.selection.is_empty() && !self.library,
            CaptureLast => self.last_area.is_some(),
            CopyImage | Export => !self.library,
            _ => true,
        }
    }

    pub fn execute(&mut self, ctx: &Context, command: Command) {
        use Command::*;
        if !self.enabled(command) {
            return;
        }
        match command {
            Tool(tool) => {
                self.tool_styles[self.tool as usize] = self.style.clone();
                self.tool = tool;
                self.style = self.tool_styles[tool as usize].clone();
                self.library = false;
                self.editing_text = None;
                if tool == crate::document::Tool::Image && self.style.image_kind == ImageKind::Image
                {
                    if let Some(path) = rfd::FileDialog::new()
                        .add_filter("Images", &["png", "jpg", "jpeg", "bmp", "webp"])
                        .pick_file()
                    {
                        match Document::read_image(&path) {
                            Ok(image) => {
                                self.history.begin(&self.doc);
                                let id = self.doc.create(tool, pos2(20., 20.), self.style.clone());
                                let form = self.doc.forms.last_mut().unwrap();
                                form.bounds[2] = image.width as f32;
                                form.bounds[3] = image.height as f32;
                                form.image = Some(image.background);
                                self.selection = BTreeSet::from([id]);
                                self.history.commit();
                                self.dirty = true;
                                self.tool = crate::document::Tool::Select;
                            }
                            Err(e) => self.error = Some(e),
                        }
                    }
                }
            }
            New => {
                self.dialog = Some(Dialog::New);
                self.dialog_size = [960, 540];
            }
            Open => {
                if let Some(path) = rfd::FileDialog::new()
                    .set_title(self.tr("Open Image…"))
                    .add_filter(
                        "Images and captures",
                        &["png", "jpg", "jpeg", "bmp", "gif", "webp", "tiff", "scc"],
                    )
                    .pick_file()
                {
                    if self.archive() {
                        self.load(path);
                    }
                }
            }
            OpenSelected => {
                if let Some(path) = self
                    .library_selected
                    .and_then(|i| self.library_entries.get(i).map(|e| e.path.clone()))
                {
                    self.load(path);
                }
            }
            Save => {
                self.save(false);
            }
            Export => {
                if let Some(path) = rfd::FileDialog::new()
                    .set_title(self.tr("Save as Image…"))
                    .add_filter("PNG", &["png"])
                    .add_filter("JPEG", &["jpg"])
                    .add_filter("Bitmap", &["bmp"])
                    .set_file_name("capture.png")
                    .save_file()
                {
                    let result = renderer::export(&self.doc).and_then(|pixels| {
                        if path.extension().is_some_and(|e| {
                            e.eq_ignore_ascii_case("jpg") || e.eq_ignore_ascii_case("jpeg")
                        }) {
                            image::DynamicImage::ImageRgba8(pixels)
                                .to_rgb8()
                                .save(&path)
                                .map_err(|e| e.to_string())
                        } else {
                            pixels.save(&path).map_err(|e| e.to_string())
                        }
                    });
                    match result {
                        Ok(()) => self.toast(self.tr("Saved")),
                        Err(e) => self.error = Some(e),
                    }
                }
            }
            CopyImage => {
                match renderer::export(&self.doc).and_then(|image| native::copy_image(&image)) {
                    Ok(()) => self.toast(self.tr("Copy Image to Clipboard")),
                    Err(e) => self.error = Some(e),
                }
            }
            PasteImage => match native::clipboard_image() {
                Ok(image) => {
                    if self.archive() {
                        self.replace(Document::from_image(image, "Clipboard"));
                        self.dirty = true;
                    }
                }
                Err(e) => self.error = Some(e),
            },
            CaptureArea | CaptureScreen | CaptureWindow | CaptureLast => {
                if self.capture_request.is_none() && self.archive() {
                    if let Err(error) = self.start_capture(ctx, command) {
                        self.error = Some(error);
                    }
                }
            }
            Library => {
                if self.archive() {
                    self.library = !self.library;
                    if self.library {
                        self.refresh_library(ctx);
                    }
                }
            }
            Undo => {
                self.history.undo(&mut self.doc);
                self.selection
                    .retain(|id| self.doc.forms.iter().any(|f| f.id == *id));
                self.dirty = true;
            }
            Redo => {
                self.history.redo(&mut self.doc);
                self.selection.clear();
                self.dirty = true;
            }
            Copy | Cut => {
                self.clipboard = self
                    .doc
                    .forms
                    .iter()
                    .filter(|f| self.selection.contains(&f.id))
                    .cloned()
                    .collect();
                if command == Cut {
                    self.execute(ctx, Delete);
                }
            }
            Paste | Duplicate => {
                let forms = if command == Duplicate {
                    self.doc
                        .forms
                        .iter()
                        .filter(|f| self.selection.contains(&f.id))
                        .cloned()
                        .collect()
                } else {
                    self.clipboard.clone()
                };
                self.history.begin(&self.doc);
                self.selection = self.doc.paste(&forms, vec2(16., 16.));
                self.history.commit();
                self.dirty = true;
            }
            Delete => {
                self.mutate(|d, s| d.forms.retain(|f| !s.contains(&f.id)));
                self.selection.clear();
            }
            SelectAll => {
                self.selection = self
                    .doc
                    .forms
                    .iter()
                    .filter(|f| !f.frozen)
                    .map(|f| f.id)
                    .collect()
            }
            Deselect => {
                self.selection.clear();
                self.editing_text = None;
            }
            InvertSelection => {
                self.selection = self
                    .doc
                    .forms
                    .iter()
                    .filter(|f| !f.frozen && !self.selection.contains(&f.id))
                    .map(|f| f.id)
                    .collect()
            }
            Group => self.mutate(|d, s| d.group(s)),
            Ungroup => self.mutate(|d, s| d.ungroup(s)),
            Freeze => self.mutate(|d, s| {
                for f in &mut d.forms {
                    if s.contains(&f.id) {
                        f.frozen = !f.frozen;
                    }
                }
            }),
            Front | Back | Forward | Backward => self.mutate(|d, s| {
                d.arrange(
                    s,
                    if matches!(command, Front | Forward) {
                        1
                    } else {
                        -1
                    },
                    matches!(command, Front | Back),
                )
            }),
            AlignLeft | AlignCenter | AlignRight | AlignTop | AlignMiddle | AlignBottom => {
                let axis = usize::from(matches!(command, AlignTop | AlignMiddle | AlignBottom));
                let factor = match command {
                    AlignCenter | AlignMiddle => 0.5,
                    AlignRight | AlignBottom => 1.,
                    _ => 0.,
                };
                self.mutate(|d, s| d.align(s, axis, factor));
            }
            Flatten => match renderer::export(&self.doc) {
                Ok(image) => {
                    self.mutate(|d, _| {
                        d.background = Arc::new(image);
                        d.background_position = [0., 0.];
                        d.forms.clear();
                    });
                    self.selection.clear();
                }
                Err(e) => self.error = Some(e),
            },
            Crop => {
                if let Some(rect) = self.doc.selection_rect(&self.selection) {
                    self.mutate(|d, s| {
                        d.forms.retain(|f| {
                            !(s.contains(&f.id) && f.tool == crate::document::Tool::PixelSelection)
                        });
                        d.crop(rect);
                    });
                    self.selection.clear();
                    self.fit = true;
                }
            }
            Resize => {
                self.dialog_size = [self.doc.width, self.doc.height];
                self.dialog = Some(Dialog::Resize);
            }
            Mirror | Flip | RotateLeft | RotateRight => {
                self.mutate(|d, _| {
                    let w = d.width as f32;
                    let h = d.height as f32;
                    let pixels = d.background_pixels();
                    d.background = Arc::new(match command {
                        Mirror => image::imageops::flip_horizontal(&*pixels),
                        Flip => image::imageops::flip_vertical(&*pixels),
                        RotateLeft => image::imageops::rotate270(&*pixels),
                        _ => image::imageops::rotate90(&*pixels),
                    });
                    d.background_position = [0., 0.];
                    for f in &mut d.forms {
                        let r = f.rect();
                        let map = |p: Pos2| match command {
                            Mirror => pos2(w - p.x, p.y),
                            Flip => pos2(p.x, h - p.y),
                            RotateLeft => pos2(p.y, w - p.x),
                            _ => pos2(h - p.y, p.x),
                        };
                        for p in &mut f.points {
                            let q = map(pos2(p[0], p[1]));
                            *p = [q.x, q.y];
                        }
                        let a = map(r.min);
                        let b = map(r.max);
                        let r = Rect::from_two_pos(a, b);
                        f.bounds = [r.min.x, r.min.y, r.width(), r.height()];
                    }
                    d.width = d.background.width();
                    d.height = d.background.height();
                });
                self.fit = true;
            }
            Restore => self.mutate(|d, _| {
                d.background = d.original.clone();
                d.background_position = [0., 0.];
                d.width = d.original.width();
                d.height = d.original.height();
            }),
            ZoomIn => {
                self.zoom = (self.zoom * 1.25).min(16.);
                self.fit = false;
            }
            ZoomOut => {
                self.zoom = (self.zoom / 1.25).max(0.05);
                self.fit = false;
            }
            ActualSize => {
                self.zoom = 1.;
                self.pan = Vec2::ZERO;
                self.fit = false;
            }
            Fit => {
                self.fit = true;
                self.pan = Vec2::ZERO;
            }
            Inspector => self.inspector = !self.inspector,
            Lens => {
                self.lens = true;
                self.lens_query.clear();
                self.lens_index = 0;
                self.lens_focus = true;
            }
            ThemeDark | ThemeLight | ThemeSystem => {
                self.settings.theme = command.label().into();
                self.apply_theme(ctx);
                self.persist();
            }
            English | French => {
                self.settings.french = command == French;
                self.strings = Strings::new(self.settings.french);
                self.persist();
            }
            About => self.dialog = Some(Dialog::About),
            Options => self.dialog = Some(Dialog::Options),
            Quit => {
                if self.dirty {
                    self.dialog = Some(Dialog::Close);
                } else {
                    self.allow_close = true;
                    ctx.send_viewport_cmd(ViewportCommand::Close);
                }
            }
            ResetSteps => self.mutate(|d, _| {
                d.next_step = 1;
            }),
            Favorite => self.mutate(|d, _| d.favorite = !d.favorite),
            ChooseLibrary => {
                if let Some(path) = rfd::FileDialog::new().pick_folder() {
                    self.settings.library = path;
                    self.persist();
                    self.refresh_library(ctx);
                }
            }
        }
    }

    fn apply_theme(&mut self, ctx: &Context) {
        self.dark = match self.settings.theme.as_str() {
            "Light" => false,
            "System" => ctx.input(|i| i.raw.system_theme) != Some(egui::Theme::Light),
            _ => true,
        };
        self.palette = Palette::new(self.dark);
        self.palette.apply(ctx, self.dark);
    }
    fn persist(&mut self) {
        if let Err(e) = self.settings.save(&self.root) {
            self.error = Some(e);
        }
    }

    fn command_button(&mut self, ui: &mut Ui, command: Command) {
        if ui
            .add_enabled(
                self.enabled(command),
                Button::new(self.tr(command.label())).frame(false),
            )
            .clicked()
        {
            self.queued.push(command);
        }
    }

    fn shortcuts(&mut self, ctx: &Context) {
        if ctx.input_mut(|i| i.consume_key(Modifiers::CTRL, Key::Space)) {
            self.execute(ctx, Command::Lens);
        }
        if self.lens || self.dialog.is_some() || ctx.wants_keyboard_input() {
            return;
        }
        let ctrl_shift = Modifiers {
            ctrl: true,
            shift: true,
            ..Modifiers::NONE
        };
        let shortcuts = [
            (Modifiers::CTRL, Key::N, Command::New),
            (Modifiers::CTRL, Key::O, Command::Open),
            (Modifiers::CTRL, Key::S, Command::Save),
            (ctrl_shift, Key::S, Command::Export),
            (Modifiers::CTRL, Key::Z, Command::Undo),
            (Modifiers::CTRL, Key::Y, Command::Redo),
            (Modifiers::CTRL, Key::C, Command::Copy),
            (Modifiers::CTRL, Key::X, Command::Cut),
            (Modifiers::CTRL, Key::V, Command::Paste),
            (Modifiers::CTRL, Key::D, Command::Duplicate),
            (Modifiers::CTRL, Key::A, Command::SelectAll),
            (ctrl_shift, Key::I, Command::InvertSelection),
            (Modifiers::CTRL, Key::G, Command::Group),
            (ctrl_shift, Key::G, Command::Ungroup),
            (ctrl_shift, Key::A, Command::CopyImage),
            (ctrl_shift, Key::N, Command::PasteImage),
            (ctrl_shift, Key::T, Command::Flatten),
            (Modifiers::NONE, Key::Delete, Command::Delete),
            (Modifiers::NONE, Key::Home, Command::Front),
            (Modifiers::NONE, Key::End, Command::Back),
            (Modifiers::NONE, Key::PageUp, Command::Forward),
            (Modifiers::NONE, Key::PageDown, Command::Backward),
            (Modifiers::NONE, Key::I, Command::Inspector),
            (Modifiers::NONE, Key::Escape, Command::Deselect),
            (Modifiers::CTRL, Key::Plus, Command::ZoomIn),
            (Modifiers::CTRL, Key::Minus, Command::ZoomOut),
            (Modifiers::CTRL, Key::Num0, Command::ActualSize),
        ];
        for (modifiers, key, command) in shortcuts {
            if ctx.input_mut(|i| i.consume_key(modifiers, key)) {
                self.queued.push(command);
            }
        }
        for (key, tool) in [
            (Key::V, Tool::Select),
            (Key::R, Tool::Shape),
            (Key::P, Tool::Polygon),
            (Key::A, Tool::Arrow),
            (Key::L, Tool::Line),
            (Key::T, Tool::Text),
            (Key::C, Tool::Callout),
            (Key::D, Tool::Draw),
            (Key::H, Tool::Highlight),
            (Key::N, Tool::Step),
            (Key::M, Tool::Image),
            (Key::X, Tool::PixelSelection),
        ] {
            if ctx.input_mut(|i| i.consume_key(Modifiers::NONE, key)) {
                self.queued.push(Command::Tool(tool));
            }
        }
        for (key, direction) in [
            (Key::ArrowLeft, vec2(-1., 0.)),
            (Key::ArrowRight, vec2(1., 0.)),
            (Key::ArrowUp, vec2(0., -1.)),
            (Key::ArrowDown, vec2(0., 1.)),
        ] {
            if ctx.input(|i| i.key_pressed(key)) {
                let delta = direction
                    * if ctx.input(|i| i.modifiers.shift) {
                        10.
                    } else {
                        1.
                    };
                self.mutate(|d, s| {
                    for f in &mut d.forms {
                        if s.contains(&f.id) && !f.frozen {
                            f.translate(delta);
                        }
                    }
                });
            }
        }
        if ctx.input(|i| i.key_pressed(Key::F2) || i.key_pressed(Key::Enter)) {
            if let Some(id) = self.selection.iter().next().copied() {
                self.editing_text = Some(id);
            }
        }
    }

    fn chrome(&mut self, ctx: &Context) {
        if self.show_caption {
            TopBottomPanel::top("strip")
                .show_separator_line(false)
                .frame(Frame::new().fill(self.palette.ground))
                .exact_height(theme::STRIP)
                .show(ctx, |ui| {
                    let r = ui.max_rect();
                    let title = ui.interact(r, ui.id().with("drag"), Sense::click_and_drag());
                    ui.painter().text(
                        r.center(),
                        Align2::CENTER_CENTER,
                        "Swag Capture",
                        FontId::proportional(12.),
                        self.palette.faint,
                    );
                    if title.drag_started() {
                        ctx.send_viewport_cmd(ViewportCommand::StartDrag);
                    }
                    if title.double_clicked() {
                        ctx.send_viewport_cmd(ViewportCommand::Maximized(
                            !ctx.input(|i| i.viewport().maximized.unwrap_or(false)),
                        ));
                    }
                    ui.scope_builder(
                        UiBuilder::new().max_rect(Rect::from_min_max(
                            pos2(r.right() - 224., r.top() + 10.),
                            r.right_bottom() - vec2(8., 10.),
                        )),
                        |ui| {
                            ui.horizontal(|ui| {
                                let search =
                                    crate::controls::quiet(ui, "    Commands", self.palette);
                                let center = search.rect.left_center() + vec2(9., -1.);
                                ui.painter().circle_stroke(
                                    center,
                                    4.,
                                    Stroke::new(1.0_f32, self.palette.soft),
                                );
                                ui.painter().line_segment(
                                    [center + vec2(3., 3.), center + vec2(6., 6.)],
                                    Stroke::new(1.0_f32, self.palette.soft),
                                );
                                if search.clicked() {
                                    self.queued.push(Command::Lens);
                                }
                                ui.add_space(8.);
                                for (label, command) in
                                    [("\u{2212}", 0), ("\u{25a1}", 1), ("\u{00d7}", 2)]
                                {
                                    if ui
                                        .add_sized(
                                            [28., 28.],
                                            Button::new(
                                                RichText::new(label)
                                                    .size(16.)
                                                    .color(self.palette.faint),
                                            )
                                            .frame(false),
                                        )
                                        .clicked()
                                    {
                                        match command {
                                            0 => ctx.send_viewport_cmd(ViewportCommand::Minimized(
                                                true,
                                            )),
                                            1 => ctx.send_viewport_cmd(ViewportCommand::Maximized(
                                                !ctx.input(|i| {
                                                    i.viewport().maximized.unwrap_or(false)
                                                }),
                                            )),
                                            _ => self.queued.push(Command::Quit),
                                        }
                                    }
                                }
                            });
                        },
                    );
                });
        }
        TopBottomPanel::top("tasks")
            .show_separator_line(false)
            .frame(
                Frame::new()
                    .fill(self.palette.ground)
                    .inner_margin(Margin::symmetric(24, 0)),
            )
            .exact_height(36.)
            .show(ctx, |ui| {
                ui.horizontal(|ui| {
                    ui.spacing_mut().item_spacing.x = 12.;
                    let (r, resp) = ui.allocate_exact_size(vec2(24., 28.), Sense::click());
                    crate::icons::paint(
                        ui.painter(),
                        r.shrink2(vec2(4., 6.)),
                        27,
                        self.palette.soft,
                    );
                    if resp.clicked() {
                        self.queued.push(Command::CaptureArea);
                    }
                    self.command_button(ui, Command::CaptureArea);
                    self.command_button(ui, Command::Library);
                    ui.add_space(24.);
                    self.command_button(ui, Command::CopyImage);
                    self.command_button(ui, Command::Export);
                });
            });
        let screen = ctx.content_rect();
        let right = if self.inspector {
            theme::INSPECTOR + theme::INSET
        } else {
            0.
        };
        Area::new("hint".into())
            .fixed_pos(pos2(90., screen.bottom() - 48.))
            .order(Order::Foreground)
            .interactable(false)
            .show(ctx, |ui| {
                ui.set_max_width((screen.width() - right - 104.).max(100.));
                ui.horizontal(|ui| {
                    ui.spacing_mut().item_spacing.x = 20.;
                    if self.library {
                        ui.label(RichText::new("Enter   open       Double-click   open       Ctrl Space   commands").size(12.).color(self.palette.faint));
                        return;
                    }
                    ui.label(
                        RichText::new(format!(
                            "{} \u{00d7} {} \u{00b7} {:.0} %",
                            self.doc.width,
                            self.doc.height,
                            self.zoom * 100.
                        ))
                        .font(FontId::monospace(12.))
                        .color(self.palette.faint),
                    );
                    let hint = if self.selection.is_empty() {
                        self.tr(match self.tool {
                            Tool::Arrow => "Drag to draw an arrow",
                            Tool::Line => "Drag to draw a line",
                            Tool::Polygon => "Drag to draw a polygon",
                            Tool::Draw => "Drag to draw freehand",
                            Tool::Highlight => "Drag to highlight",
                            Tool::Text => "Click to add text",
                            Tool::Step => "Click to add a step",
                            Tool::Select => "Click to select, drag to move",
                            _ => "Drag to draw a rectangle or an ellipse",
                        })
                    } else {
                        self.tr("\u{2190} \u{2191} \u{2192} \u{2193}   nudge, Shift \u{00d7}10")
                    };
                    ui.label(RichText::new(hint).size(12.).color(self.palette.faint));
                    ui.label(
                        RichText::new(if self.selection.is_empty() {
                            "Ctrl Space"
                        } else {
                            "Ctrl D   duplicate"
                        })
                        .size(12.)
                        .color(self.palette.faint),
                    );
                });
            });
    }

    fn dock(&mut self, ctx: &Context, area: Rect) {
        Area::new("dock".into())
            .fixed_pos(pos2(
                area.min.x + theme::INSET,
                area.center().y - (8. * theme::CELL + 7. * 2. + 12.) / 2.,
            ))
            .show(ctx, |ui| {
                self.palette.frame().inner_margin(6).show(ui, |ui| {
                    ui.spacing_mut().item_spacing = vec2(0., 2.);
                    for group in [
                        vec![Tool::Select],
                        vec![Tool::Shape, Tool::Polygon],
                        vec![Tool::Arrow, Tool::Line],
                        vec![Tool::Text],
                        vec![Tool::Callout],
                        vec![Tool::Draw, Tool::Highlight],
                        vec![Tool::Step],
                        vec![Tool::Image, Tool::PixelSelection],
                    ] {
                        let tool = if group.contains(&self.tool) {
                            self.tool
                        } else {
                            group[0]
                        };
                        let (rect, response) =
                            ui.allocate_exact_size(vec2(theme::CELL, theme::CELL), Sense::click());
                        if tool == self.tool {
                            ui.painter()
                                .rect_filled(rect.shrink(2.), 6, self.palette.selection);
                        } else if response.hovered() {
                            ui.painter()
                                .rect_filled(rect.shrink(2.), 6, self.palette.raised);
                        }
                        crate::icons::tool(
                            ui.painter(),
                            Rect::from_center_size(rect.center(), vec2(16., 16.)),
                            tool,
                            if tool == self.tool {
                                self.palette.arc
                            } else {
                                self.palette.soft
                            },
                        );
                        if group.len() > 1 {
                            ui.painter().line_segment(
                                [
                                    rect.right_bottom() - vec2(6., 3.),
                                    rect.right_bottom() - vec2(3., 6.),
                                ],
                                Stroke::new(1.0_f32, self.palette.faint),
                            );
                        }
                        if response.clicked() {
                            self.queued.push(Command::Tool(tool));
                        }
                        response.clone().on_hover_text(self.tr(tool.name()));
                        response.context_menu(|ui| {
                            for tool in &group {
                                if ui.button(self.tr(tool.name())).clicked() {
                                    self.queued.push(Command::Tool(*tool));
                                    ui.close();
                                }
                            }
                        });
                    }
                });
            });
    }

    fn canvas(&mut self, ui: &mut Ui) {
        let area = ui.max_rect();
        let right = if self.inspector && area.width() >= 800. {
            theme::INSPECTOR + theme::INSET
        } else {
            0.
        };
        let work = Rect::from_min_max(area.min + vec2(66., 0.), area.max - vec2(right + 2., 0.));
        if self.fit {
            self.zoom = (work.width() / self.doc.width as f32)
                .min(work.height() / self.doc.height as f32)
                .min(1.)
                .max(0.05);
            self.pan = Vec2::ZERO;
            self.fit = false;
        }
        let origin = work.center() - self.doc.rect().size() * self.zoom / 2. + self.pan;
        let canvas_rect = Rect::from_min_size(origin, self.doc.rect().size() * self.zoom);
        let response = ui.allocate_rect(area, Sense::click_and_drag());
        self.renderer
            .paint(ui.painter(), &self.doc, origin, self.zoom);
        if !self.lens && self.dialog.is_none() {
            self.canvas_input(ui, &response, origin, canvas_rect);
        }
        let arc = self.palette.arc;
        for point in crate::gizmo::anchors(canvas_rect) {
            let r = Rect::from_center_size(point, vec2(10., 10.));
            ui.painter().rect_filled(r, 0, Color32::WHITE);
            ui.painter()
                .rect_stroke(r, 0, Stroke::new(1.0_f32, arc), StrokeKind::Inside);
        }
        for form in &self.doc.forms {
            if self.selection.contains(&form.id) {
                crate::gizmo::paint(ui.painter(), form, origin, self.zoom, arc);
            }
        }
        if let Some(Drag::Marquee { start, end }) = &self.drag {
            let r = Rect::from_two_pos(
                origin + start.to_vec2() * self.zoom,
                origin + end.to_vec2() * self.zoom,
            );
            ui.painter().rect_filled(r, 0, arc.gamma_multiply(0.12));
            ui.painter()
                .rect_stroke(r, 0, Stroke::new(1.0_f32, arc), StrokeKind::Middle);
        }
        self.dock(ui.ctx(), area);
        if self.inspector && area.width() >= 800. {
            self.inspector_ui(ui.ctx(), area);
        }
        if let Some(r) = self.doc.selection_rect(&self.selection) {
            let text = self.doc.forms.iter().any(|f| {
                self.selection.contains(&f.id) && matches!(f.tool, Tool::Text | Tool::Callout)
            });
            let width = if text { 515. } else { 240. };
            let top = origin.y + r.top() * self.zoom;
            let y = if top - 48. < canvas_rect.top() && top > canvas_rect.top() {
                canvas_rect.top() - 48.
            } else {
                top - 48.
            };
            self.minibar(
                ui.ctx(),
                pos2(
                    (origin.x + r.center().x * self.zoom - width / 2.).clamp(
                        area.left() + 78.,
                        (area.right() - right - width - 12.).max(area.left() + 78.),
                    ),
                    y.max(area.top() + 4.),
                ),
            );
        }
        self.text_editor(ui.ctx(), origin);
    }

    fn canvas_input(&mut self, ui: &mut Ui, response: &Response, origin: Pos2, canvas: Rect) {
        let ctx = ui.ctx();
        if response.hovered() {
            let (scroll, ctrl) = ctx.input(|i| (i.raw_scroll_delta, i.modifiers.ctrl));
            if scroll != Vec2::ZERO {
                if ctrl {
                    let old = self.zoom;
                    self.zoom = (self.zoom * (scroll.y * 0.002).exp()).clamp(0.05, 16.);
                    if let Some(pointer) = response.hover_pos() {
                        self.pan += (pointer - canvas.center()) * (1. - self.zoom / old);
                    }
                } else {
                    self.pan += scroll;
                }
            }
        }
        let Some(pointer) = response.interact_pointer_pos() else {
            return;
        };
        let point = ((pointer - origin) / self.zoom).to_pos2();
        if response.drag_started_by(PointerButton::Middle)
            || (response.drag_started() && ctx.input(|i| i.key_down(Key::Space)))
        {
            self.drag = Some(Drag::Pan { start: self.pan });
        } else if response.drag_started_by(PointerButton::Primary) {
            self.editing_text = None;
            let start = ctx.input(|i| i.pointer.press_origin()).unwrap_or(pointer);
            let start = ((start - origin) / self.zoom).to_pos2();
            let handle = self
                .doc
                .forms
                .iter()
                .filter(|f| self.selection.contains(&f.id) && !f.frozen)
                .find_map(|f| {
                    crate::gizmo::handles(f, self.zoom)
                        .into_iter()
                        .find(|(_, p)| p.distance(start) * self.zoom < 8.)
                        .map(|(handle, _)| (f.clone(), handle))
                });
            if let Some((original, handle)) = handle {
                self.history.begin(&self.doc);
                self.drag = Some(Drag::Handle {
                    id: original.id,
                    original,
                    start,
                    handle,
                });
            } else if self.tool == Tool::Select
                || !self.doc.select_at(start, 5. / self.zoom).is_empty()
            {
                let hit = self.doc.select_at(start, 5. / self.zoom);
                if hit.is_empty() {
                    if !ctx.input(|i| i.modifiers.shift) {
                        self.selection.clear();
                    }
                    self.drag = Some(Drag::Marquee { start, end: point });
                } else {
                    if !hit.is_subset(&self.selection) {
                        if ctx.input(|i| i.modifiers.shift) {
                            self.selection.extend(hit);
                        } else {
                            self.selection = hit;
                        }
                    }
                    self.history.begin(&self.doc);
                    self.drag = Some(Drag::Move {
                        start,
                        forms: self.doc.forms.clone(),
                    });
                }
            } else if self.tool != Tool::Step
                && canvas.contains(origin + start.to_vec2() * self.zoom)
            {
                self.history.begin(&self.doc);
                let id = self.doc.create(self.tool, start, self.style.clone());
                self.selection = BTreeSet::from([id]);
                self.drag = Some(Drag::Create { id, start });
            }
        }
        if response.clicked()
            && (self.tool == Tool::Select || !self.doc.select_at(point, 5. / self.zoom).is_empty())
        {
            let hit = self.doc.select_at(point, 5. / self.zoom);
            if ctx.input(|i| i.modifiers.shift) {
                for id in hit {
                    if !self.selection.remove(&id) {
                        self.selection.insert(id);
                    }
                }
            } else {
                self.selection = hit;
            }
        }
        if response.double_clicked() {
            self.editing_text = self.doc.select_at(point, 5. / self.zoom).first().copied();
        }
        if response.clicked()
            && self.tool == Tool::Step
            && self.doc.select_at(point, 5. / self.zoom).is_empty()
        {
            self.history.begin(&self.doc);
            let id = self
                .doc
                .create(Tool::Step, point - vec2(24., 24.), self.style.clone());
            self.doc.forms.last_mut().unwrap().bounds[2..].copy_from_slice(&[48., 48.]);
            self.selection = BTreeSet::from([id]);
            self.history.commit();
            self.dirty = true;
        }
        if let Some(drag) = &mut self.drag {
            match drag {
                Drag::Create { id, start } => {
                    if let Some(form) = self.doc.forms.iter_mut().find(|f| f.id == *id) {
                        form.draw_to(*start, point, ctx.input(|i| i.modifiers.shift));
                    }
                }
                Drag::Move { start, forms } => {
                    let mut delta = point - *start;
                    if ctx.input(|i| i.modifiers.shift) {
                        if delta.x.abs() > delta.y.abs() {
                            delta.y = 0.;
                        } else {
                            delta.x = 0.;
                        }
                    }
                    delta = vec2(delta.x.round(), delta.y.round());
                    if self.settings.snap && !ctx.input(|i| i.modifiers.alt) {
                        if let Some(first) = forms.iter().find(|f| self.selection.contains(&f.id)) {
                            let r = first.rect().translate(delta);
                            for other in forms.iter().filter(|f| !self.selection.contains(&f.id)) {
                                for x in [
                                    other.rect().min.x,
                                    other.rect().center().x,
                                    other.rect().max.x,
                                ] {
                                    if (r.min.x - x).abs() * self.zoom < 5. {
                                        delta.x += x - r.min.x;
                                        break;
                                    }
                                }
                                for y in [
                                    other.rect().min.y,
                                    other.rect().center().y,
                                    other.rect().max.y,
                                ] {
                                    if (r.min.y - y).abs() * self.zoom < 5. {
                                        delta.y += y - r.min.y;
                                        break;
                                    }
                                }
                            }
                        }
                    }
                    for form in &mut self.doc.forms {
                        if self.selection.contains(&form.id) && !form.frozen {
                            if let Some(original) = forms.iter().find(|f| f.id == form.id) {
                                *form = original.clone();
                                form.translate(delta);
                            }
                        }
                    }
                }
                Drag::Handle {
                    id,
                    original,
                    start,
                    handle,
                } => {
                    if let Some(form) = self.doc.forms.iter_mut().find(|f| f.id == *id) {
                        *form = original.clone();
                        match *handle {
                            crate::gizmo::Handle::Edge(anchor) => {
                                form.set_rect(crate::gizmo::resize(
                                    original.rect(),
                                    anchor,
                                    point - *start,
                                    original.style.rotation,
                                    ctx.input(|i| i.modifiers.shift && !i.modifiers.ctrl),
                                ))
                            }
                            crate::gizmo::Handle::Rotate => {
                                let center = original.rect().center();
                                let delta = ((point - center).angle() - (*start - center).angle())
                                    .to_degrees();
                                let mut angle = (original.style.rotation + delta).rem_euclid(360.);
                                if ctx.input(|i| i.modifiers.shift) {
                                    angle = (angle / 15.).round() * 15.;
                                }
                                form.style.rotation = angle;
                            }
                            crate::gizmo::Handle::Point(index) => {
                                form.points[index] = [point.x, point.y];
                                let rect = Rect::from_points(&form.path_points());
                                form.bounds = [
                                    rect.left(),
                                    rect.top(),
                                    rect.width().max(1.),
                                    rect.height().max(1.),
                                ];
                            }
                            crate::gizmo::Handle::Control => form.control = [point.x, point.y],
                            crate::gizmo::Handle::Tail => {
                                let p = original.rect().center()
                                    + crate::gizmo::rotate(
                                        point - original.rect().center(),
                                        -original.style.rotation,
                                    );
                                form.tail = [p.x, p.y];
                            }
                        }
                    }
                }
                Drag::Marquee { end, .. } => *end = point,
                Drag::Pan { start } => self.pan = *start + response.drag_delta(),
            }
        }
        if response.drag_stopped() || response.drag_stopped_by(PointerButton::Middle) {
            if let Some(drag) = self.drag.take() {
                match drag {
                    Drag::Marquee { start, end } => {
                        let r = Rect::from_two_pos(start, end);
                        self.selection.extend(
                            self.doc
                                .forms
                                .iter()
                                .filter(|f| !f.frozen && r.contains_rect(f.rect()))
                                .map(|f| f.id),
                        );
                    }
                    Drag::Pan { .. } => {}
                    Drag::Create { id, .. } => {
                        self.history.commit();
                        self.dirty = true;
                        if matches!(self.tool, Tool::Text | Tool::Callout) {
                            self.editing_text = Some(id);
                        }
                    }
                    _ => {
                        self.history.commit();
                        self.dirty = true;
                    }
                }
            }
        }
        if ctx.input(|i| i.key_pressed(Key::Escape)) && self.drag.is_some() {
            self.history.cancel(&mut self.doc);
            self.drag = None;
        }
        response.context_menu(|ui| {
            for c in [
                Command::Copy,
                Command::Paste,
                Command::Duplicate,
                Command::Delete,
                Command::Group,
                Command::Ungroup,
                Command::Front,
                Command::Back,
            ] {
                self.command_button(ui, c);
            }
        });
    }

    fn apply_style(&mut self, before: &Style, after: &Style) {
        if before == after {
            return;
        }
        if self.selection.is_empty() {
            self.style = after.clone();
            self.tool_styles[self.tool as usize] = after.clone();
        } else {
            self.history.begin(&self.doc);
            for form in &mut self.doc.forms {
                if self.selection.contains(&form.id) {
                    form.style.apply_changed(before, after);
                }
            }
            self.dirty = true;
        }
    }

    fn inspector_ui(&mut self, ctx: &Context, area: Rect) {
        use crate::controls as c;
        let selected = self
            .selection
            .first()
            .and_then(|id| self.doc.forms.iter().position(|f| f.id == *id));
        let tool = selected
            .map(|i| self.doc.forms[i].tool)
            .unwrap_or(self.tool);
        let mut style = selected
            .map(|i| self.doc.forms[i].style.clone())
            .unwrap_or_else(|| self.style.clone());
        let before = style.clone();
        let p = self.palette;
        Area::new("inspector".into())
            .fixed_pos(pos2(
                area.right() - theme::INSET - theme::INSPECTOR,
                area.top() + theme::INSET,
            ))
            .show(ctx, |ui| {
                p.frame().show(ui, |ui| {
                    ui.set_width(264.);
                    ui.set_height((area.height() - 88.).max(200.));
                    ui.spacing_mut().item_spacing = vec2(6., 0.);
                    ui.allocate_ui_with_layout(
                        vec2(264., 30.),
                        Layout::left_to_right(Align::Center),
                        |ui| {
                            ui.label(
                                RichText::new(self.tr(tool.name()))
                                    .font(FontId::new(15., FontFamily::Name("Inter Bold".into())))
                                    .color(p.text),
                            );
                            ui.label(
                                RichText::new(if self.selection.is_empty() {
                                    self.tr("new objects")
                                } else {
                                    format!(
                                        "{} {}",
                                        self.selection.len(),
                                        if self.selection.len() == 1 {
                                            "object"
                                        } else {
                                            "objects"
                                        }
                                    )
                                })
                                .font(FontId::monospace(11.))
                                .color(p.faint),
                            );
                            if !self.selection.is_empty() {
                                ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                                    if c::quiet(ui, &self.tr("Delete"), p).clicked() {
                                        self.queued.push(Command::Delete);
                                    }
                                    if c::quiet(ui, &self.tr("Duplicate"), p).clicked() {
                                        self.queued.push(Command::Duplicate);
                                    }
                                });
                            }
                        },
                    );
                    ui.add_space(10.);
                    ui.horizontal(|ui| {
                        let defaults: Vec<_> = [
                            [232, 8, 8, 255],
                            [96, 196, 71, 255],
                            [25, 156, 244, 255],
                            [253, 223, 27, 255],
                            [232, 8, 8, 255],
                        ]
                        .into_iter()
                        .map(|rgba| {
                            let mut preset = Style::for_tool(tool);
                            if matches!(
                                tool,
                                Tool::Shape | Tool::Polygon | Tool::Arrow | Tool::Line | Tool::Draw
                            ) {
                                preset.outline = rgba;
                            } else {
                                preset.fill = rgba;
                            }
                            preset
                        })
                        .collect();
                        let presets = self
                            .settings
                            .presets
                            .get(tool as usize)
                            .filter(|p| !p.is_empty())
                            .unwrap_or(&defaults);
                        for (index, preset) in presets.iter().take(5).enumerate() {
                            let rgba = if matches!(
                                tool,
                                Tool::Shape | Tool::Polygon | Tool::Arrow | Tool::Line | Tool::Draw
                            ) {
                                preset.outline
                            } else {
                                preset.fill
                            };
                            let (r, response) =
                                ui.allocate_exact_size(vec2(38., 32.), Sense::click());
                            ui.painter().rect_filled(
                                r,
                                6,
                                if response.hovered() {
                                    p.selection
                                } else {
                                    p.raised
                                },
                            );
                            let col =
                                Color32::from_rgba_unmultiplied(rgba[0], rgba[1], rgba[2], rgba[3]);
                            if matches!(tool, Tool::Arrow | Tool::Line) {
                                c::line_preset(
                                    ui,
                                    r.shrink(3.),
                                    preset,
                                    ui.id().with(("line-preset", tool as usize, index)),
                                );
                            } else if matches!(tool, Tool::Text | Tool::Callout) {
                                let font = FontId::new(13., FontFamily::Name("Inter Bold".into()));
                                for offset in
                                    [vec2(-1., 0.), vec2(1., 0.), vec2(0., -1.), vec2(0., 1.)]
                                {
                                    ui.painter().text(
                                        r.center() + offset,
                                        Align2::CENTER_CENTER,
                                        "Aa",
                                        font.clone(),
                                        Color32::WHITE,
                                    );
                                }
                                ui.painter().text(
                                    r.center(),
                                    Align2::CENTER_CENTER,
                                    "Aa",
                                    font,
                                    col,
                                );
                            } else if matches!(tool, Tool::Shape | Tool::Polygon) {
                                ui.painter().rect_stroke(
                                    r.shrink2(vec2(9., 9.)),
                                    if preset.shape == ShapeKind::Rounded {
                                        8
                                    } else {
                                        0
                                    },
                                    Stroke::new(2.0_f32, col),
                                    StrokeKind::Inside,
                                );
                            } else {
                                draw_glyph(ui.painter(), r.shrink2(vec2(10., 8.)), tool, col);
                            }
                            if response.clicked() {
                                style = preset.clone();
                            }
                            if style == *preset {
                                ui.painter().rect_stroke(
                                    r.expand(2.),
                                    7,
                                    Stroke::new(1.5_f32, p.arc),
                                    StrokeKind::Outside,
                                );
                            }
                            response.on_hover_text(format!("{} {}", self.tr("Style"), index + 1));
                        }
                        ui.menu_button("...", |ui| {
                            for (index, preset) in presets.iter().enumerate().skip(5) {
                                if ui
                                    .button(format!("{} {}", self.tr("Style"), index + 1))
                                    .clicked()
                                {
                                    style = preset.clone();
                                    ui.close();
                                }
                            }
                            if ui.button(self.tr("Reset")).clicked() {
                                style = Style::for_tool(tool);
                                ui.close();
                            }
                        });
                    });
                    ScrollArea::vertical()
                        .max_height((area.height() - 170.).max(100.))
                        .show(ui, |ui| {
                            self.section(ui, "Color");
                            let line = matches!(
                                tool,
                                Tool::Line | Tool::Arrow | Tool::Draw | Tool::Highlight
                            );
                            if line {
                                c::color(ui, &self.tr("Color"), &mut style.outline, p);
                                c::color(ui, &self.tr("Outline"), &mut style.line_outline_color, p);
                            } else {
                                c::color(ui, &self.tr("Fill"), &mut style.fill, p);
                                style.filled = style.fill[3] != 0;
                                c::color(ui, &self.tr("Outline"), &mut style.outline, p);
                            }
                            if tool == Tool::Callout {
                                c::color(ui, &self.tr("Text"), &mut style.text_color, p);
                            }
                            if matches!(tool, Tool::Text | Tool::Callout) {
                                self.section(ui, "Text");
                                c::row(ui, &self.tr("Font"), |ui| {
                                    ComboBox::from_id_salt("font")
                                        .width(154.)
                                        .selected_text(&style.font_name)
                                        .show_ui(ui, |ui| {
                                            for name in [
                                                "Inter",
                                                "Roboto Mono",
                                                "Arial",
                                                "Segoe UI",
                                                "Times New Roman",
                                                "Consolas",
                                            ] {
                                                ui.selectable_value(
                                                    &mut style.font_name,
                                                    name.into(),
                                                    name,
                                                );
                                            }
                                        });
                                });
                                c::slider(
                                    ui,
                                    &self.tr("Size"),
                                    &mut style.font_size,
                                    10.0..=150.,
                                    "",
                                    p,
                                );
                                c::row(ui, &self.tr("Style"), |ui| {
                                    let mut face = style.bold as u32 | ((style.italic as u32) << 1);
                                    c::segments(ui, &mut face, &["Aa", "Aa", "Aa", "Aa"], p);
                                    style.bold = face & 1 != 0;
                                    style.italic = face & 2 != 0;
                                });
                                c::slider(
                                    ui,
                                    &self.tr("Strength"),
                                    &mut style.bold_size,
                                    0.0..=20.,
                                    "",
                                    p,
                                );
                                c::slider(
                                    ui,
                                    &self.tr("Line Spacing"),
                                    &mut style.line_spacing,
                                    0.0..=80.,
                                    "",
                                    p,
                                );
                            }
                            if matches!(tool, Tool::Shape | Tool::Polygon | Tool::Step) {
                                self.section(ui, "Style");
                                let mut shape = style.shape as u32;
                                c::row(ui, &self.tr("Kind"), |ui| {
                                    c::segments(
                                        ui,
                                        &mut shape,
                                        &["\u{25cb}", "\u{25a1}", "\u{25a2}"],
                                        p,
                                    )
                                });
                                style.shape = match shape {
                                    1 => ShapeKind::Rectangle,
                                    2 => ShapeKind::Rounded,
                                    _ => ShapeKind::Ellipse,
                                };
                            }
                            if !matches!(
                                tool,
                                Tool::Text | Tool::Image | Tool::Callout | Tool::Step
                            ) {
                                if line {
                                    self.section(ui, "Style");
                                }
                                c::line_choices(ui, &self.tr("Dash"), &mut style.dash, false, p);
                            }
                            if matches!(tool, Tool::Line | Tool::Arrow) {
                                c::line_choices(
                                    ui,
                                    &self.tr("Start"),
                                    &mut style.begin_cap,
                                    true,
                                    p,
                                );
                                c::line_choices(ui, &self.tr("End"), &mut style.end_cap, true, p);
                            }
                            if tool == Tool::Step {
                                c::choice(
                                    ui,
                                    &self.tr("Numbering"),
                                    &mut style.numbering,
                                    &["1...2...3...", "A...B...C...", "a...b...c..."],
                                );
                            }
                            if (tool == Tool::Shape && style.shape == ShapeKind::Rounded)
                                || tool == Tool::Callout
                            {
                                self.section(ui, "Shape");
                                c::slider(
                                    ui,
                                    &self.tr("Round"),
                                    &mut style.radius,
                                    10.0..=50.,
                                    "",
                                    p,
                                );
                            }
                            if tool == Tool::Image {
                                self.section(ui, "Image");
                                let mut kind = style.image_kind as u32;
                                c::choice(
                                    ui,
                                    &self.tr("Kind"),
                                    &mut kind,
                                    &["Image", "Blur", "Pixelate", "Zoom"],
                                );
                                style.image_kind = match kind {
                                    1 => ImageKind::Blur,
                                    2 => ImageKind::Pixelate,
                                    3 => ImageKind::Zoom,
                                    _ => ImageKind::Image,
                                };
                                let mut strength = style.strength as f32;
                                c::slider(
                                    ui,
                                    &self.tr("Strength"),
                                    &mut strength,
                                    0.0..=100.,
                                    "",
                                    p,
                                );
                                style.strength = strength as u32;
                            }
                            self.section(ui, "Stroke");
                            if line {
                                c::slider(
                                    ui,
                                    &self.tr("Outline"),
                                    &mut style.line_outline,
                                    0.0..=20.,
                                    "",
                                    p,
                                );
                            }
                            c::slider(
                                ui,
                                &self.tr(if tool == Tool::Text {
                                    "Outline"
                                } else {
                                    "Thickness"
                                }),
                                &mut style.thickness,
                                0.0..=if tool == Tool::Text { 20. } else { 100. },
                                "",
                                p,
                            );
                            if !matches!(tool, Tool::Line | Tool::Arrow) {
                                c::choice(
                                    ui,
                                    &self.tr("Joins"),
                                    &mut style.join,
                                    &["None", "Bevel", "Round", "Miter", "Miter Bevel"],
                                );
                            }
                            if matches!(tool, Tool::Line | Tool::Arrow) {
                                let mut curve = style.bezier as u32;
                                c::row(ui, &self.tr("Line"), |ui| {
                                    c::segments(
                                        ui,
                                        &mut curve,
                                        &[&self.tr("Straight"), &self.tr("Bezier")],
                                        p,
                                    );
                                });
                                style.bezier = curve != 0;
                                if style.begin_cap >= 4 || style.end_cap >= 4 {
                                    self.section(ui, "Ends");
                                }
                                if style.begin_cap >= 4 {
                                    c::slider(
                                        ui,
                                        &self.tr("Start Size"),
                                        &mut style.start_size,
                                        1.0..=8.,
                                        "",
                                        p,
                                    );
                                }
                                if style.end_cap >= 4 {
                                    c::slider(
                                        ui,
                                        &self.tr("End Size"),
                                        &mut style.arrow_size,
                                        1.0..=8.,
                                        "",
                                        p,
                                    );
                                }
                            }
                            self.section(ui, "Effects");
                            if matches!(tool, Tool::Text | Tool::Callout) {
                                c::slider(
                                    ui,
                                    &self.tr("Scale"),
                                    &mut style.scale,
                                    0.0..=100.,
                                    " %",
                                    p,
                                );
                            }
                            if !matches!(tool, Tool::Line | Tool::Arrow) {
                                c::slider(
                                    ui,
                                    &self.tr("Rotate"),
                                    &mut style.rotation,
                                    0.0..=360.,
                                    " \u{00b0}",
                                    p,
                                );
                            }
                            c::slider(
                                ui,
                                &self.tr("Opacity"),
                                &mut style.opacity,
                                0.0..=100.,
                                " %",
                                p,
                            );
                            let mut shadow = style.shadow as u32;
                            c::row(ui, &self.tr("Shadow"), |ui| {
                                c::segments(
                                    ui,
                                    &mut shadow,
                                    &[&self.tr("None"), &self.tr("Small")],
                                    p,
                                );
                            });
                            style.shadow = shadow != 0;
                            if let Some(index) = selected {
                                self.section(ui, "Dimensions");
                                let mut bounds = self.doc.forms[index].bounds;
                                let mut changed = false;
                                for (label, indices) in [("Position", [0, 1]), ("Size", [2, 3])] {
                                    c::row(ui, &self.tr(label), |ui| {
                                        for i in indices {
                                            changed |= ui
                                                .add_sized(
                                                    [78., 28.],
                                                    DragValue::new(&mut bounds[i]).speed(1.),
                                                )
                                                .changed();
                                        }
                                    });
                                }
                                if changed {
                                    self.history.begin(&self.doc);
                                    self.doc.forms[index].set_rect(Rect::from_min_size(
                                        pos2(bounds[0], bounds[1]),
                                        vec2(bounds[2].max(1.), bounds[3].max(1.)),
                                    ));
                                    self.dirty = true;
                                }
                            }
                        });
                });
            });
        self.apply_style(&before, &style);
        if !ctx.input(|i| i.pointer.any_down()) && !ctx.wants_keyboard_input() {
            self.history.commit();
        }
    }

    fn section(&self, ui: &mut Ui, title: &str) {
        ui.add_space(16.);
        ui.label(
            RichText::new(self.tr(title).to_uppercase())
                .size(10.)
                .color(self.palette.faint),
        );
        ui.add_space(4.);
    }

    fn minibar(&mut self, ctx: &Context, point: Pos2) {
        let selected = self
            .selection
            .first()
            .and_then(|id| self.doc.forms.iter().position(|f| f.id == *id));
        let Some(index) = selected else {
            return;
        };
        let tool = self.doc.forms[index].tool;
        let mut style = self.doc.forms[index].style.clone();
        let before = style.clone();
        let p = self.palette;
        Area::new("minibar".into())
            .fixed_pos(point)
            .show(ctx, |ui| {
                p.frame().corner_radius(8).inner_margin(4).show(ui, |ui| {
                    ui.spacing_mut().item_spacing = vec2(2., 0.);
                    ui.horizontal(|ui| {
                        if self.selection.len() == 1 {
                            ui.scope(|ui| {
                                ui.spacing_mut().interact_size = vec2(24., 24.);
                                ui.color_edit_button_srgba_unmultiplied(
                                    if matches!(
                                        tool,
                                        Tool::Arrow | Tool::Line | Tool::Draw | Tool::Highlight
                                    ) {
                                        &mut style.outline
                                    } else {
                                        &mut style.fill
                                    },
                                );
                            });
                            ui.add_space(8.);
                            ui.separator();
                            ui.add_space(8.);
                            if matches!(tool, Tool::Text | Tool::Callout) {
                                ComboBox::from_id_salt("mini-font")
                                    .width(64.)
                                    .selected_text(&style.font_name)
                                    .show_ui(ui, |ui| {
                                        for name in [
                                            "Inter",
                                            "Roboto Mono",
                                            "Arial",
                                            "Segoe UI",
                                            "Times New Roman",
                                            "Consolas",
                                        ] {
                                            ui.selectable_value(
                                                &mut style.font_name,
                                                name.into(),
                                                name,
                                            );
                                        }
                                    });
                                ui.add_sized(
                                    [46., 28.],
                                    DragValue::new(&mut style.font_size)
                                        .range(10.0..=150.)
                                        .max_decimals(0),
                                );
                                ui.separator();
                                for (label, active) in
                                    [("B", &mut style.bold), ("I", &mut style.italic)]
                                {
                                    if ui
                                        .add_sized(
                                            [28., 28.],
                                            Button::new(label).selected(*active).frame(*active),
                                        )
                                        .clicked()
                                    {
                                        *active = !*active;
                                    }
                                }
                                ui.separator();
                                for vertical in [false, true] {
                                    for (align, glyph) in [
                                        (0, if vertical { 34 } else { 31 }),
                                        (2, if vertical { 35 } else { 32 }),
                                        (1, if vertical { 36 } else { 33 }),
                                    ] {
                                        let active = if vertical {
                                            style.align_v == align
                                        } else {
                                            style.align_h == align
                                        };
                                        let (r, response) =
                                            ui.allocate_exact_size(vec2(28., 28.), Sense::click());
                                        if active {
                                            ui.painter().rect_filled(r, 5, p.selection);
                                            ui.painter().rect_stroke(
                                                r,
                                                5,
                                                Stroke::new(1.0_f32, p.arc.gamma_multiply(0.4)),
                                                StrokeKind::Inside,
                                            );
                                        }
                                        crate::icons::paint(
                                            ui.painter(),
                                            Rect::from_center_size(r.center(), vec2(16., 16.)),
                                            glyph,
                                            if active { p.arc } else { p.soft },
                                        );
                                        if response.clicked() {
                                            if vertical {
                                                style.align_v = align
                                            } else {
                                                style.align_h = align
                                            }
                                        }
                                    }
                                    ui.separator();
                                }
                            } else if tool == Tool::Step {
                                let mut step = self.doc.forms[index].step;
                                if ui
                                    .add_sized([88., 28.], DragValue::new(&mut step).range(1..=999))
                                    .changed()
                                {
                                    self.mutate(|d, _| d.forms[index].step = step);
                                }
                            }
                        } else {
                            for command in [
                                Command::AlignLeft,
                                Command::AlignCenter,
                                Command::AlignRight,
                                Command::AlignTop,
                                Command::AlignMiddle,
                                Command::AlignBottom,
                                Command::Group,
                            ] {
                                self.command_button(ui, command);
                            }
                        }
                        if ui
                            .add_sized([28., 28.], Button::new("\u{00d7}").frame(false))
                            .on_hover_text(self.tr("Delete"))
                            .clicked()
                        {
                            self.queued.push(Command::Delete);
                        }
                        ui.menu_button("...", |ui| {
                            for command in [
                                Command::Duplicate,
                                Command::Delete,
                                Command::Group,
                                Command::Ungroup,
                                Command::Front,
                                Command::Back,
                                Command::Forward,
                                Command::Backward,
                                Command::Freeze,
                            ] {
                                self.command_button(ui, command);
                            }
                        });
                    });
                });
            });
        self.apply_style(&before, &style);
        if !ctx.input(|i| i.pointer.any_down()) && !ctx.wants_keyboard_input() {
            self.history.commit();
        }
    }

    fn text_editor(&mut self, ctx: &Context, origin: Pos2) {
        let Some(id) = self.editing_text else {
            return;
        };
        let Some(index) = self
            .doc
            .forms
            .iter()
            .position(|f| f.id == id && matches!(f.tool, Tool::Text | Tool::Callout))
        else {
            self.editing_text = None;
            return;
        };
        let r = self.doc.forms[index].rect();
        let point = origin + r.min.to_vec2() * self.zoom;
        let mut text = self.doc.forms[index].text.clone();
        Area::new("text-editor".into())
            .fixed_pos(point)
            .order(Order::Foreground)
            .show(ctx, |ui| {
                let edit = ui.add_sized(
                    vec2(
                        (r.width() * self.zoom).max(120.),
                        (r.height() * self.zoom).max(60.),
                    ),
                    TextEdit::multiline(&mut text).font(FontId::proportional(
                        self.doc.forms[index].style.font_size * self.zoom,
                    )),
                );
                if !edit.has_focus() && self.doc.forms[index].text.is_empty() {
                    edit.request_focus();
                }
                if edit.changed() {
                    self.history.begin(&self.doc);
                    self.doc.forms[index].text = text;
                    self.dirty = true;
                }
                if ctx.input(|i| {
                    i.key_pressed(Key::Escape) || (i.modifiers.ctrl && i.key_pressed(Key::Enter))
                }) {
                    self.editing_text = None;
                    self.history.commit();
                }
            });
    }

    fn lens_ui(&mut self, ctx: &Context) {
        if !self.lens {
            return;
        }
        let mut chosen = None;
        let p = self.palette;
        let modal = egui::Modal::new("lens".into())
            .frame(p.frame().inner_margin(24))
            .show(ctx, |ui| {
                ui.set_width(570.);
                let step = ctx.input_mut(|i| {
                    i.consume_key(Modifiers::NONE, Key::ArrowDown) as i32
                        - i.consume_key(Modifiers::NONE, Key::ArrowUp) as i32
                });
                let enter = ctx.input_mut(|i| i.consume_key(Modifiers::NONE, Key::Enter));
                let edit = ui.add(
                    TextEdit::singleline(&mut self.lens_query)
                        .hint_text(self.strings.text("Search commands\u{2026}"))
                        .font(FontId::proportional(22.))
                        .frame(false)
                        .desired_width(f32::INFINITY),
                );
                if self.lens_focus {
                    edit.request_focus();
                    self.lens_focus = false;
                }
                if edit.changed() {
                    self.lens_index = 0;
                }
                ui.add_space(16.);
                let query = self.lens_query.trim().to_lowercase();
                let mut commands: Vec<_> = Command::all()
                    .into_iter()
                    .filter(|c| {
                        if *c == Command::Lens || (!self.library && *c == Command::OpenSelected) {
                            return false;
                        }
                        if self.library && matches!(c.group(), "Selection" | "Tools" | "View") {
                            return false;
                        }
                        if self.library
                            && c.group() == "Image"
                            && !matches!(c, Command::New | Command::Open | Command::PasteImage)
                        {
                            return false;
                        }
                        let label = self.tr(c.label()).to_lowercase();
                        query.split_whitespace().all(|word| {
                            label.contains(word) || c.label().to_lowercase().contains(word)
                        })
                    })
                    .collect();
                let groups = if self.library {
                    [
                        "Library",
                        "Capture",
                        "Image",
                        "Tools",
                        "Selection",
                        "View",
                        "Application",
                    ]
                } else if self.selection.is_empty() {
                    [
                        "Capture",
                        "Tools",
                        "Image",
                        "Library",
                        "Selection",
                        "View",
                        "Application",
                    ]
                } else {
                    [
                        "Selection",
                        "Tools",
                        "Image",
                        "Capture",
                        "Library",
                        "View",
                        "Application",
                    ]
                };
                commands.sort_by_key(|c| groups.iter().position(|g| *g == c.group()).unwrap_or(7));
                let available: Vec<_> = commands
                    .iter()
                    .enumerate()
                    .filter_map(|(i, c)| self.enabled(*c).then_some(i))
                    .collect();
                if let Some(first) = available.first() {
                    let current = available
                        .iter()
                        .position(|i| *i == self.lens_index)
                        .unwrap_or(0);
                    self.lens_index = available
                        [(current as i32 + step).rem_euclid(available.len() as i32) as usize];
                    if edit.changed() {
                        self.lens_index = *first;
                    }
                    if enter {
                        chosen = Some(commands[self.lens_index]);
                    }
                }
                ScrollArea::vertical().max_height(420.).show(ui, |ui| {
                    let mut group = "";
                    for (index, c) in commands.iter().copied().enumerate() {
                        if group != c.group() {
                            group = c.group();
                            ui.add_space(10.);
                            ui.label(
                                RichText::new(self.tr(group).to_uppercase())
                                    .size(10.)
                                    .color(p.faint),
                            );
                            ui.add_space(5.);
                        }
                        let enabled = self.enabled(c);
                        let (rect, response) =
                            ui.allocate_exact_size(vec2(570., 36.), Sense::click());
                        if enabled
                            && response.hovered()
                            && ctx.input(|i| i.pointer.delta() != Vec2::ZERO)
                        {
                            self.lens_index = index;
                        }
                        let selected = enabled && self.lens_index == index;
                        if selected {
                            ui.painter().rect_filled(rect, 6, p.selection);
                            if step != 0 || edit.changed() {
                                response.scroll_to_me(Some(Align::Center));
                            }
                        }
                        let label = if c == Command::Library && self.library {
                            self.tr("Editor")
                        } else {
                            self.tr(c.label())
                        };
                        ui.painter().text(
                            rect.left_center() + vec2(12., 0.),
                            Align2::LEFT_CENTER,
                            label,
                            FontId::proportional(14.),
                            if enabled { p.text } else { p.faint },
                        );
                        ui.painter().text(
                            rect.right_center() - vec2(12., 0.),
                            Align2::RIGHT_CENTER,
                            c.shortcut(),
                            FontId::monospace(11.),
                            p.faint,
                        );
                        if enabled && response.clicked() {
                            chosen = Some(c);
                        }
                    }
                    if commands.is_empty() {
                        ui.label(self.tr("No commands found"));
                    }
                });
                ui.add_space(16.);
                ui.label(
                    RichText::new("\u{2191} \u{2193}    \u{00b7}    Enter    \u{00b7}    Esc")
                        .monospace()
                        .color(p.faint),
                );
            });
        if modal.should_close() {
            self.lens = false;
        }
        if let Some(command) = chosen {
            self.lens = false;
            self.queued.push(command);
        }
    }

    fn dialog_ui(&mut self, ctx: &Context) {
        let Some(dialog) = self.dialog else {
            return;
        };
        let mut close = false;
        let result = Modal::new("dialog".into())
            .frame(self.palette.frame().inner_margin(28))
            .show(ctx, |ui| {
                ui.set_width(440.);
                let title = match dialog {
                    Dialog::New => "New Image",
                    Dialog::Resize => "Resize Image…",
                    Dialog::About => "Swag Capture",
                    Dialog::Options => "Options…",
                    Dialog::Close => "Save changes?",
                };
                ui.label(RichText::new(self.tr(title)).size(21.).strong());
                ui.add_space(16.);
                match dialog {
                    Dialog::New | Dialog::Resize => {
                        ui.label(self.tr("Width"));
                        ui.add(DragValue::new(&mut self.dialog_size[0]).range(16..=MAX_SIZE));
                        ui.label(self.tr("Height"));
                        ui.add(DragValue::new(&mut self.dialog_size[1]).range(16..=MAX_SIZE));
                    }
                    Dialog::About => {
                        ui.label("Rust comparison build · 0.1.0");
                        ui.hyperlink_to("Source", "https://github.com/swag-lang/swag");
                        ui.collapsing("Third-party notices", |ui| {
                            ScrollArea::vertical().max_height(280.).show(ui, |ui| {
                                ui.add(Label::new(theme::LICENSES).wrap());
                            });
                        });
                    }
                    Dialog::Options => {
                        let cursor = self.tr("Capture Mouse Cursor");
                        ui.checkbox(&mut self.settings.capture_cursor, cursor);
                        let snap = self.tr("Snap to Forms");
                        ui.checkbox(&mut self.settings.snap, snap);
                        ui.label(self.tr("Delay Before Capture"));
                        ui.add(Slider::new(&mut self.settings.capture_delay, 0..=9).suffix(" s"));
                        ui.add_space(16.);
                        ui.horizontal(|ui| {
                            for c in [
                                Command::ThemeDark,
                                Command::ThemeLight,
                                Command::ThemeSystem,
                            ] {
                                self.command_button(ui, c);
                            }
                        });
                        ui.horizontal(|ui| {
                            for c in [Command::English, Command::French] {
                                self.command_button(ui, c);
                            }
                        });
                        self.command_button(ui, Command::ChooseLibrary);
                    }
                    Dialog::Close => {}
                }
                ui.add_space(16.);
                ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                    let primary = match dialog {
                        Dialog::New => "Create",
                        Dialog::Resize => "Resize",
                        Dialog::Close => "Save",
                        _ => "Close",
                    };
                    if ui
                        .add(
                            Button::new(RichText::new(self.tr(primary)).color(if self.dark {
                                Color32::BLACK
                            } else {
                                Color32::WHITE
                            }))
                            .fill(self.palette.primary),
                        )
                        .clicked()
                    {
                        match dialog {
                            Dialog::New => {
                                if self.archive() {
                                    self.replace(Document::blank(
                                        self.dialog_size[0],
                                        self.dialog_size[1],
                                    ));
                                    self.dirty = true;
                                    close = true;
                                }
                            }
                            Dialog::Resize => {
                                let [w, h] = self.dialog_size;
                                self.mutate(|d, _| d.resize(w, h));
                                self.fit = true;
                                close = true;
                            }
                            Dialog::Close => {
                                if self.save(false) {
                                    self.allow_close = true;
                                    ctx.send_viewport_cmd(ViewportCommand::Close);
                                    close = true;
                                }
                            }
                            Dialog::Options => {
                                self.persist();
                                close = true;
                            }
                            Dialog::About => close = true,
                        }
                    }
                    if matches!(dialog, Dialog::New | Dialog::Resize | Dialog::Close)
                        && ui.button(self.tr("Cancel")).clicked()
                    {
                        close = true;
                    }
                    if dialog == Dialog::Close && ui.button(self.tr("Discard")).clicked() {
                        self.allow_close = true;
                        ctx.send_viewport_cmd(ViewportCommand::Close);
                        close = true;
                    }
                });
            });
        if close || result.should_close() {
            self.dialog = None;
        }
    }

    fn refresh_library(&mut self, ctx: &Context) {
        self.library_entries.clear();
        self.library_selected = None;
        self.library_indexed = false;
        self.library_preview_count = 0;
        self.library_loader = None;
        match crate::library::Loader::new(self.settings.library.clone(), ctx.clone()) {
            Ok(loader) => self.library_loader = Some(loader),
            Err(error) => self.error = Some(error),
        }
    }

    fn poll_library(&mut self, ctx: &Context) {
        use crate::library::Event as LibraryEvent;
        for _ in 0..16 {
            let Some(event) = self
                .library_loader
                .as_ref()
                .and_then(|loader| loader.events.try_recv().ok())
            else {
                break;
            };
            match event {
                LibraryEvent::Files(paths) => {
                    self.library_indexed = paths.is_empty();
                    self.library_entries = paths
                        .into_iter()
                        .map(|path| LibraryEntry {
                            title: path
                                .file_stem()
                                .unwrap_or_default()
                                .to_string_lossy()
                                .into(),
                            path,
                            texture: None,
                            favorite: false,
                            rating: 0,
                            metadata: None,
                            pending: false,
                            error: None,
                            last_visible: 0,
                        })
                        .collect();
                }
                LibraryEvent::Metadata(index, result) => {
                    if let Some(entry) = self.library_entries.get_mut(index) {
                        match result {
                            Ok(metadata) => {
                                if !metadata.title.is_empty() {
                                    entry.title = metadata.title.clone();
                                }
                                entry.favorite = metadata.favorite;
                                entry.rating = metadata.rating;
                                entry.metadata = Some(metadata);
                            }
                            Err(error) => entry.error = Some(error),
                        }
                    }
                }
                LibraryEvent::Preview(index, result) => {
                    if let Some(entry) = self.library_entries.get_mut(index) {
                        entry.pending = false;
                        match result {
                            Ok(preview) => {
                                entry.texture = Some(ctx.load_texture(
                                    entry.path.to_string_lossy(),
                                    ColorImage::from_rgba_unmultiplied(
                                        [preview.width() as usize, preview.height() as usize],
                                        preview.as_raw(),
                                    ),
                                    TextureOptions::LINEAR,
                                ));
                                self.library_preview_count += 1;
                            }
                            Err(error) => entry.error = Some(error),
                        }
                    }
                }
                LibraryEvent::Indexed => self.library_indexed = true,
            }
        }
        // Keep only recently visible GPU thumbnails; source images never enter this cache.
        let cached = self
            .library_entries
            .iter()
            .filter(|e| e.texture.is_some())
            .count();
        if cached > 64 {
            let mut oldest: Vec<_> = self
                .library_entries
                .iter()
                .enumerate()
                .filter(|(_, e)| e.texture.is_some())
                .map(|(i, e)| (e.last_visible, i))
                .collect();
            oldest.sort_unstable();
            for (_, index) in oldest.into_iter().take(cached - 64) {
                self.library_entries[index].texture = None;
            }
        }
    }

    fn library_ui(&mut self, ui: &mut Ui) {
        self.poll_library(ui.ctx());
        let p = self.palette;
        let mut open = None;
        let mut choose_folder = false;
        let mut visible_pending = 0;
        let mut visible_images = 0;
        let mut visible_last = 0;
        let bounds = Rect::from_min_max(
            ui.max_rect().min + vec2(72., 24.),
            ui.max_rect().max - vec2(72., 56.),
        );
        ui.scope_builder(
            UiBuilder::new()
                .max_rect(bounds)
                .layout(Layout::top_down(Align::Min)),
            |ui| {
                ui.allocate_ui_with_layout(
                    vec2(bounds.width(), 60.),
                    Layout::left_to_right(Align::Center),
                    |ui| {
                        ui.label(
                            RichText::new(self.tr("Library"))
                                .font(FontId::new(48., FontFamily::Name("Inter Bold".into()))),
                        );
                        ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                            ui.add_sized(
                                [278., 30.],
                                TextEdit::singleline(&mut self.library_query)
                                    .hint_text(self.strings.text("Search")),
                            );
                            ui.menu_button(self.strings.text("Folders"), |ui| {
                                choose_folder = ui
                                    .button(self.strings.text("Choose Folder\u{2026}"))
                                    .clicked();
                                ui.label(self.settings.library.to_string_lossy());
                            });
                            ui.menu_button(self.strings.text("Filter"), |ui| {
                                ui.checkbox(
                                    &mut self.library_favorites,
                                    self.strings.text("Favorites Only"),
                                );
                            });
                        });
                    },
                );
                ui.allocate_ui_with_layout(
                    vec2(bounds.width(), 48.),
                    Layout::left_to_right(Align::Center),
                    |ui| {
                        ui.label(
                            RichText::new(format!(
                                "{}  {}",
                                self.strings.text("All Items"),
                                self.library_entries.len()
                            ))
                            .color(p.text),
                        );
                        if !self.library_indexed {
                            ui.spinner();
                        }
                    },
                );
                ui.add_space(24.);
                let query = self.library_query.to_lowercase();
                let filtered: Vec<_> = self
                    .library_entries
                    .iter()
                    .enumerate()
                    .filter(|(_, entry)| {
                        (!self.library_favorites || entry.favorite)
                            && (query.is_empty()
                                || entry.title.to_lowercase().contains(&query)
                                || entry
                                    .metadata
                                    .as_ref()
                                    .is_some_and(|m| m.tags.to_lowercase().contains(&query)))
                    })
                    .map(|(i, _)| i)
                    .collect();
                let width = bounds.width();
                let columns = ((width + 32.) / (128. * 4. / 3. + 32.)).floor().max(1.) as usize;
                let tile_width = (width - 32. * columns.saturating_sub(1) as f32) / columns as f32;
                let image_height = tile_width * 0.75;
                let row_height = image_height + 70.;
                let rows = filtered.len().div_ceil(columns);
                let viewport_height = (bounds.bottom() - ui.cursor().top()).max(1.);
                let mut scroll = ScrollArea::vertical()
                    .id_salt("capture-library")
                    .max_height(viewport_height)
                    .auto_shrink([false, false]);
                if self.library_smoke && self.library_indexed {
                    let fraction = match self.library_smoke_stage {
                        0 => 0.,
                        1 => 0.5,
                        _ => 1.,
                    };
                    scroll = scroll.vertical_scroll_offset(
                        (rows as f32 * (row_height + ui.spacing().item_spacing.y)
                            - viewport_height)
                            .max(0.)
                            * fraction,
                    );
                }
                scroll.show_rows(ui, row_height, rows, |ui, row_range| {
                    for row in row_range {
                        let (_, row_rect) = ui.allocate_space(vec2(width, row_height));
                        for (column, index) in filtered
                            .iter()
                            .skip(row * columns)
                            .take(columns)
                            .copied()
                            .enumerate()
                        {
                            let rect = Rect::from_min_size(
                                row_rect.min + vec2(column as f32 * (tile_width + 32.), 0.),
                                vec2(tile_width, image_height),
                            );
                            if !ui.is_rect_visible(rect) {
                                continue;
                            }
                            visible_last = visible_last.max(index);
                            let entry = &mut self.library_entries[index];
                            entry.last_visible = self.frames;
                            let card =
                                Rect::from_min_size(rect.min, vec2(tile_width, image_height + 42.));
                            let response = ui.interact(card, ui.id().with(index), Sense::click());
                            let painter =
                                ui.painter().with_clip_rect(card.intersect(ui.clip_rect()));
                            painter.rect_filled(rect, 6, p.surface);
                            if entry.texture.is_none() && entry.error.is_none() {
                                visible_pending += 1;
                                if entry.metadata.is_some() && !entry.pending {
                                    if let Some(loader) = &self.library_loader {
                                        loader.request_preview(index);
                                        entry.pending = true;
                                    }
                                }
                            }
                            if let Some(texture) = &entry.texture {
                                visible_images += 1;
                                let image_ratio = texture.size_vec2().x / texture.size_vec2().y;
                                let tile_ratio = rect.width() / rect.height();
                                let uv_size = if image_ratio > tile_ratio {
                                    vec2(tile_ratio / image_ratio, 1.)
                                } else {
                                    vec2(1., image_ratio / tile_ratio)
                                };
                                painter.image(
                                    texture.id(),
                                    rect,
                                    Rect::from_center_size(pos2(0.5, 0.5), uv_size),
                                    Color32::WHITE,
                                );
                            } else if entry.error.is_some() {
                                painter.text(
                                    rect.center(),
                                    Align2::CENTER_CENTER,
                                    "Preview unavailable",
                                    FontId::proportional(12.),
                                    p.faint,
                                );
                            }
                            if self.library_selected == Some(index) {
                                ui.painter().rect_stroke(
                                    rect.expand(3.),
                                    7,
                                    Stroke::new(2.0_f32, p.arc),
                                    StrokeKind::Outside,
                                );
                            }
                            if response.clicked() {
                                self.library_selected = Some(index);
                            }
                            if response.double_clicked() {
                                open = Some(entry.path.clone());
                            }
                            if let Some(error) = &entry.error {
                                response.on_hover_text(error);
                            }
                            painter.text(
                                rect.left_bottom() + vec2(0., 10.),
                                Align2::LEFT_TOP,
                                &entry.title,
                                FontId::proportional(13.),
                                p.soft,
                            );
                            if entry.favorite || entry.rating > 0 {
                                painter.text(
                                    rect.left_bottom() + vec2(0., 28.),
                                    Align2::LEFT_TOP,
                                    format!("\u{2605} {}", entry.rating),
                                    FontId::monospace(11.),
                                    p.faint,
                                );
                            }
                            if let Some(metadata) = &entry.metadata {
                                painter.text(
                                    rect.right_bottom() + vec2(0., 28.),
                                    Align2::RIGHT_TOP,
                                    format!("{}\u{00d7}{}", metadata.width, metadata.height),
                                    FontId::monospace(11.),
                                    p.faint,
                                );
                            }
                        }
                    }
                });
            },
        );
        self.library_visible_images = visible_images;
        self.library_last_visible = visible_last;
        if choose_folder {
            self.queued.push(Command::ChooseLibrary);
        }
        if ui.input(|i| i.key_pressed(Key::Enter)) && !ui.ctx().wants_keyboard_input() {
            open = self
                .library_selected
                .and_then(|i| self.library_entries.get(i).map(|e| e.path.clone()));
        }
        if self.library_entries.is_empty() && self.library_indexed {
            ui.label(self.tr("No captures"));
        }
        if self.library_smoke && self.library_indexed && visible_pending == 0 && visible_images > 0
        {
            self.library_smoke_frames += 1;
            if self.library_smoke_frames >= 20 && self.library_smoke_stage < 3 {
                self.library_smoke_stage += 1;
                self.library_smoke_frames = 0;
            }
        }
        if let Some(path) = open {
            self.load(path);
        }
    }

    fn start_capture(&mut self, ctx: &Context, mode: Command) -> Result<(), String> {
        let window = native::WindowToken::active()?;
        let restore = window.rect()?;
        let scale = ctx.zoom_factor();
        if self.settings.hide_before_capture {
            window.hide();
        }
        let delay = Duration::from_millis(
            self.settings.capture_delay as u64 * 1000
                + if self.settings.hide_before_capture {
                    200
                } else {
                    0
                },
        );
        let region = if mode == Command::CaptureLast {
            self.last_area
        } else {
            None
        };
        match native::capture_async(
            window,
            mode == Command::CaptureWindow,
            region,
            self.settings.capture_cursor,
            delay,
            ctx.clone(),
        ) {
            Ok(result) => {
                self.capture_request = Some(CaptureRequest {
                    mode,
                    result,
                    window,
                    restore,
                    scale,
                })
            }
            Err(error) => {
                window.show();
                return Err(error);
            }
        }
        Ok(())
    }

    fn accept_capture(&mut self, image: image::RgbaImage) {
        if self.settings.capture_to_clipboard {
            if let Err(error) = native::copy_image(&image) {
                self.error = Some(error);
            }
        }
        if self.settings.capture_to_editor {
            self.replace(Document::from_image(image, "Screen"));
            self.dirty = true;
        }
    }

    fn poll_capture(&mut self, ctx: &Context) {
        let Some(request) = self.capture_request.as_ref() else {
            return;
        };
        let outcome = match request.result.try_recv() {
            Ok(result) => result,
            Err(std::sync::mpsc::TryRecvError::Empty) => return,
            Err(std::sync::mpsc::TryRecvError::Disconnected) => {
                Err("Screen capture stopped before returning a result.".into())
            }
        };
        let request = self.capture_request.take().unwrap();
        request.window.show();
        match outcome {
            Ok(captured) => {
                if request.mode == Command::CaptureArea {
                    self.overlay = Some(Overlay {
                        image: Arc::new(captured.image),
                        desktop: captured.rect,
                        start: None,
                        restore: request.restore,
                        scale: request.scale,
                        window: request.window,
                    });
                    ctx.set_pixels_per_point(1.);
                    request.window.place_client(captured.rect);
                } else {
                    self.accept_capture(captured.image);
                }
            }
            Err(error) => self.error = Some(error),
        }
        ctx.send_viewport_cmd(ViewportCommand::Focus);
        ctx.request_repaint();
    }

    fn overlay_ui(&mut self, ctx: &Context) {
        if (ctx.pixels_per_point() - 1.).abs() > 0.001 {
            ctx.set_pixels_per_point(1.);
            ctx.request_repaint();
        }
        let mut selection = None;
        let mut cancel = ctx.input(|i| i.key_pressed(Key::Escape));
        if let Some(overlay) = &mut self.overlay {
            if let Ok(rect) = overlay.window.client_rect() {
                if (rect.x, rect.y, rect.width, rect.height)
                    != (
                        overlay.desktop.x,
                        overlay.desktop.y,
                        overlay.desktop.width,
                        overlay.desktop.height,
                    )
                {
                    overlay.window.place_client(overlay.desktop);
                    ctx.request_repaint();
                }
            }
            CentralPanel::default().frame(Frame::NONE).show(ctx, |ui| {
                let r = ui.max_rect();
                let texture = self.renderer.texture(ctx, &overlay.image);
                ui.painter().image(
                    texture,
                    r,
                    Rect::from_min_max(Pos2::ZERO, pos2(1., 1.)),
                    Color32::WHITE,
                );
                let response = ui.allocate_rect(r, Sense::click_and_drag());
                if self.settings.capture_cross {
                    if let Some(pointer) = response.hover_pos() {
                        ui.painter().line_segment(
                            [pos2(r.left(), pointer.y), pos2(r.right(), pointer.y)],
                            Stroke::new(1.0_f32, Color32::WHITE),
                        );
                        ui.painter().line_segment(
                            [pos2(pointer.x, r.top()), pos2(pointer.x, r.bottom())],
                            Stroke::new(1.0_f32, Color32::WHITE),
                        );
                    }
                }
                if response.drag_started() {
                    overlay.start = ctx.input(|i| i.pointer.press_origin());
                }
                if let (Some(start), Some(end)) = (overlay.start, response.interact_pointer_pos()) {
                    let selected = Rect::from_two_pos(start, end).intersect(r);
                    let dim = Color32::from_black_alpha(100);
                    for mask in [
                        Rect::from_min_max(r.min, pos2(r.max.x, selected.min.y)),
                        Rect::from_min_max(pos2(r.min.x, selected.max.y), r.max),
                        Rect::from_min_max(
                            pos2(r.min.x, selected.min.y),
                            pos2(selected.min.x, selected.max.y),
                        ),
                        Rect::from_min_max(
                            pos2(selected.max.x, selected.min.y),
                            pos2(r.max.x, selected.max.y),
                        ),
                    ] {
                        ui.painter().rect_filled(mask, 0, dim);
                    }
                    ui.painter().rect_stroke(
                        selected,
                        0,
                        Stroke::new(1.0_f32, self.palette.arc),
                        StrokeKind::Outside,
                    );
                    ui.painter().text(
                        selected.min - vec2(0., 20.),
                        Align2::LEFT_BOTTOM,
                        format!("{} × {}", selected.width() as u32, selected.height() as u32),
                        FontId::monospace(14.),
                        Color32::WHITE,
                    );
                    if response.drag_stopped() && selected.width() >= 1. && selected.height() >= 1.
                    {
                        selection = Some(selected);
                    }
                } else {
                    ui.painter()
                        .rect_filled(r, 0, Color32::from_black_alpha(50));
                }
                cancel |= response.secondary_clicked();
            });
        }
        if cancel || selection.is_some() {
            self.finish_overlay(ctx, selection);
        }
    }

    fn finish_overlay(&mut self, ctx: &Context, selection: Option<Rect>) {
        let Some(overlay) = self.overlay.take() else {
            return;
        };
        ctx.set_zoom_factor(overlay.scale);
        overlay.window.place(overlay.restore, false);
        overlay.window.show();
        if let Some(r) = selection {
            let r = r.intersect(Rect::from_min_size(
                Pos2::ZERO,
                vec2(overlay.image.width() as f32, overlay.image.height() as f32),
            ));
            if !r.is_positive() {
                return;
            }
            let x = r.min.x.max(0.) as u32;
            let y = r.min.y.max(0.) as u32;
            let w = (r.width() as u32).min(overlay.image.width() - x);
            let h = (r.height() as u32).min(overlay.image.height() - y);
            let image = image::imageops::crop_imm(&*overlay.image, x, y, w, h).to_image();
            self.last_area = Some(native::ScreenRect {
                x: overlay.desktop.x + x as i32,
                y: overlay.desktop.y + y as i32,
                width: w as i32,
                height: h as i32,
            });
            self.accept_capture(image);
        }
        ctx.request_repaint();
        ctx.send_viewport_cmd(ViewportCommand::Focus);
    }

    fn drive_capture_smoke(&mut self, ctx: &Context) {
        if !self.capture_smoke || self.capture_smoke_stage >= 8 || self.capture_request.is_some() {
            return;
        }
        ctx.request_repaint();
        if self.error.is_some() && self.capture_smoke_stage != 7 {
            self.capture_smoke_stage = 8;
            return;
        }
        let visible = || native::WindowToken::active().is_ok_and(|window| window.visible());
        match self.capture_smoke_stage {
            0 if self.frames >= 5 => {
                self.dirty = false;
                self.execute(ctx, Command::CaptureScreen);
                self.capture_smoke_stage = 1;
            }
            1 if visible() => {
                if self.doc.source != "Screen" || self.doc.width == 0 {
                    self.error = Some("Full-screen capture did not reach the editor.".into());
                }
                self.capture_checks
                    .push("screen capture restored the editor".into());
                self.capture_smoke_stage = 2;
            }
            2 | 4 => {
                self.dirty = false;
                self.execute(ctx, Command::CaptureArea);
                self.capture_smoke_stage += 1;
                self.capture_smoke_ticks = 0;
            }
            3 | 5 if self.overlay.is_some() => {
                self.capture_smoke_ticks += 1;
                if self.capture_smoke_ticks < 8 {
                    return;
                }
                if let Some(overlay) = &self.overlay {
                    let size = ctx.content_rect().size();
                    if (size.x - overlay.image.width() as f32).abs() > 1.
                        || (size.y - overlay.image.height() as f32).abs() > 1.
                    {
                        self.error = Some("The capture overlay does not map one screen pixel to one selection pixel.".into());
                    }
                }
                let accepted = self.capture_smoke_stage == 3;
                self.finish_overlay(
                    ctx,
                    accepted.then(|| Rect::from_min_size(pos2(40., 40.), vec2(256., 160.))),
                );
                if (self.doc.width, self.doc.height) != (256, 160) || !visible() {
                    self.error = Some(
                        "Area capture did not preserve the selection or restore the editor.".into(),
                    );
                }
                self.capture_checks.push(
                    if accepted {
                        "area selection reached the editor"
                    } else {
                        "cancel restored the editor without replacing its capture"
                    }
                    .into(),
                );
                self.capture_smoke_stage += 1;
            }
            6 => {
                self.dirty = false;
                self.last_area = Some(native::ScreenRect {
                    x: 0,
                    y: 0,
                    width: 0,
                    height: 0,
                });
                self.execute(ctx, Command::CaptureLast);
                self.capture_smoke_stage = 7;
            }
            7 if visible() => {
                if self.error.as_deref() == Some("Invalid capture dimensions.") {
                    self.error = None;
                    self.capture_checks
                        .push("capture failure restored the editor".into());
                } else {
                    self.error = Some("The failing capture did not report its error.".into());
                }
                self.capture_smoke_stage = 8;
                self.dirty = false;
            }
            _ => {}
        }
    }

    pub fn ui(&mut self, ctx: &Context) {
        if self.fonts_pending {
            ctx.set_fonts(theme::fonts_for(
                self.doc
                    .forms
                    .iter()
                    .map(|f| f.style.font_name.as_str())
                    .chain(
                        self.settings
                            .presets
                            .iter()
                            .flatten()
                            .map(|s| s.font_name.as_str()),
                    ),
            ));
            self.fonts_pending = false;
            ctx.request_repaint();
            return;
        }
        let start = Instant::now();
        self.poll_capture(ctx);
        self.drive_capture_smoke(ctx);
        if self.overlay.is_some() {
            self.overlay_ui(ctx);
            return;
        }
        if ctx.input(|i| i.viewport().close_requested()) && !self.allow_close && self.dirty {
            ctx.send_viewport_cmd(ViewportCommand::CancelClose);
            self.dialog = Some(Dialog::Close);
        }
        self.shortcuts(ctx);
        self.chrome(ctx);
        CentralPanel::default()
            .frame(Frame::new().fill(self.palette.ground).inner_margin(0))
            .show(ctx, |ui| {
                if self.library {
                    self.library_ui(ui);
                } else {
                    self.canvas(ui);
                }
            });
        self.lens_ui(ctx);
        self.dialog_ui(ctx);
        if let Some(error) = self.error.clone() {
            let mut close = false;
            let modal = Modal::new("error".into())
                .frame(self.palette.frame().inner_margin(28))
                .show(ctx, |ui| {
                    ui.set_width(440.);
                    ui.strong(self.tr("The operation failed."));
                    ui.add_space(16.);
                    ui.label(RichText::new(error).monospace().color(self.palette.faint));
                    ui.add_space(16.);
                    if ui.button(self.tr("Close")).clicked() {
                        close = true;
                    }
                });
            if close || modal.should_close() {
                self.error = None;
            }
        }
        if let Some((message, when)) = &self.message {
            if when.elapsed() < Duration::from_secs(3) {
                Area::new("toast".into())
                    .anchor(Align2::CENTER_BOTTOM, vec2(0., -60.))
                    .order(Order::Foreground)
                    .show(ctx, |ui| {
                        self.palette.frame().inner_margin(12).show(ui, |ui| {
                            ui.label(message);
                        });
                    });
                ctx.request_repaint_after(Duration::from_secs(3) - when.elapsed());
            }
        }
        for command in std::mem::take(&mut self.queued) {
            self.execute(ctx, command);
        }
        for file in ctx.input(|i| i.raw.dropped_files.clone()) {
            if let Some(path) = file.path {
                if self.archive() {
                    self.load(path);
                }
            }
        }
        self.frames += 1;
        if self.report.is_some() {
            let elapsed_ms = start.elapsed().as_secs_f64() * 1000.;
            self.frame_times.push(elapsed_ms);
            if self.drag.is_some()
                || ctx.input(|input| {
                    input.pointer.button_down(PointerButton::Primary)
                        && input.pointer.delta().length_sq() > 0.0
                })
            {
                self.drag_frame_times.push(elapsed_ms);
            }
        }
        if self.frames == 1 {
            self.first_frame_ms = Some(self.started.elapsed().as_secs_f64() * 1000.);
        }
        if ((self.frames == 8 && !self.library_smoke && !self.capture_smoke)
            || (self.capture_smoke
                && self.capture_smoke_stage >= 8
                && !self.library_screenshot_requested)
            || (self.library_smoke
                && self.library_smoke_stage >= 3
                && !self.library_screenshot_requested))
            && self.screenshot.is_some()
        {
            self.library_screenshot_requested = true;
            ctx.send_viewport_cmd(ViewportCommand::Screenshot(Default::default()));
        }
        for event in ctx.input(|i| i.events.clone()) {
            if let Event::Screenshot { image, .. } = event {
                if let Some(path) = self.screenshot.take() {
                    let pixels: Vec<u8> = image
                        .pixels
                        .iter()
                        .flat_map(|p| p.to_srgba_unmultiplied())
                        .collect();
                    if let Err(e) = image::save_buffer(
                        path,
                        &pixels,
                        image.width() as u32,
                        image.height() as u32,
                        image::ColorType::Rgba8,
                    ) {
                        self.error = Some(e.to_string());
                    }
                }
            }
        }
        if let Some(limit) = self.benchmark_frames {
            let phase = self.frames as f32 * 0.02;
            self.zoom = 0.75 + 0.25 * phase.sin();
            self.pan = vec2(phase.cos() * 40., phase.sin() * 30.);
            if self.frames >= limit {
                self.finish_report(ctx);
            }
            ctx.request_repaint();
        } else if let Some(limit) = self.smoke_frames {
            if self.frames >= limit
                && self.screenshot.is_none()
                && (!self.library_smoke || self.library_smoke_stage >= 3)
                && (!self.capture_smoke || self.capture_smoke_stage >= 8)
            {
                self.finish_report(ctx);
            }
            ctx.request_repaint();
        }
    }

    fn finish_report(&mut self, ctx: &Context) {
        if let Some(path) = self.report.take() {
            let mut samples = self
                .frame_times
                .iter()
                .copied()
                .skip(10)
                .collect::<Vec<_>>();
            samples.sort_by(f64::total_cmp);
            let percentile = |p: f64| {
                samples
                    .get(((samples.len().saturating_sub(1)) as f64 * p) as usize)
                    .copied()
                    .unwrap_or_default()
            };
            let memory = native::memory_bytes();
            let mut drag_samples = self.drag_frame_times.clone();
            drag_samples.sort_by(f64::total_cmp);
            let drag_percentile = |p: f64| {
                drag_samples
                    .get(((drag_samples.len().saturating_sub(1)) as f64 * p) as usize)
                    .copied()
                    .unwrap_or_default()
            };
            let report = serde_json::json!({ "application": "swagcapture-rust", "frames": self.frames,
                "objects": self.doc.forms.len(), "width": self.doc.width, "height": self.doc.height,
                "first_ui_update_ms": self.first_frame_ms, "ui_update_median_ms": percentile(0.5),
                "ui_update_p95_ms": percentile(0.95), "wall_ms": self.started.elapsed().as_secs_f64() * 1000.,
                "drag_frames": drag_samples.len(), "drag_ui_update_median_ms": drag_percentile(0.5),
                "drag_ui_update_p95_ms": drag_percentile(0.95), "drag_ui_update_worst_ms": drag_samples.last().copied().unwrap_or_default(),
                "working_set_bytes": memory.0, "private_bytes": memory.1,
                "opened_capture": self.path, "library": self.settings.library,
                "theme": self.settings.theme, "tool": self.tool.name(), "snap": self.settings.snap,
                "library_entries": self.library_entries.len(), "library_indexed": self.library_indexed,
                "library_previews_loaded": self.library_preview_count,
                "library_visible_images": self.library_visible_images,
                "library_last_visible": self.library_last_visible,
                "library_smoke_stage": self.library_smoke_stage,
                "capture_checks": self.capture_checks,
                "library_errors": self.library_entries.iter().filter_map(|e| e.error.as_ref().map(|error|
                    serde_json::json!({"path": e.path, "error": error}))).collect::<Vec<_>>(),
                "scope": "CPU application UI update, including form hit testing and painting; drag samples are updates during an active app drag or primary-button pointer movement. Excludes egui tessellation, GPU execution and presentation.",
                "parity_verified": false, "errors": self.error });
            if let Err(e) = storage::atomic_write(
                &path,
                serde_json::to_string_pretty(&report).unwrap().as_bytes(),
            ) {
                self.error = Some(e);
            }
        }
        self.allow_close = true;
        ctx.send_viewport_cmd(ViewportCommand::Close);
    }
}

impl eframe::App for CaptureApp {
    fn update(&mut self, ctx: &Context, _frame: &mut eframe::Frame) {
        self.ui(ctx);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn frame(app: &mut CaptureApp, ctx: &Context, time: f64, events: Vec<Event>) {
        let _ = ctx.run(
            RawInput {
                screen_rect: Some(Rect::from_min_size(Pos2::ZERO, vec2(1200., 800.))),
                time: Some(time),
                events,
                ..Default::default()
            },
            |ctx| app.ui(ctx),
        );
    }

    fn pointer(pos: Pos2, pressed: bool) -> Event {
        Event::PointerButton {
            pos,
            button: PointerButton::Primary,
            pressed,
            modifiers: Modifiers::NONE,
        }
    }

    #[test]
    fn capture_overlay_mouse_drag_and_escape_follow_screen_coordinates() {
        let ctx = Context::default();
        let mut app = CaptureApp::new(
            &ctx,
            std::env::temp_dir().join("capture-overlay-input-test"),
        );
        app.settings.capture_to_clipboard = false;
        let pixels = Arc::new(image::RgbaImage::from_fn(1200, 800, |x, y| {
            image::Rgba([x as u8, y as u8, 17, 255])
        }));
        let overlay = || Overlay {
            image: pixels.clone(),
            desktop: native::ScreenRect {
                x: -1200,
                y: 20,
                width: 1200,
                height: 800,
            },
            start: None,
            restore: native::ScreenRect {
                x: 0,
                y: 0,
                width: 1200,
                height: 800,
            },
            window: native::WindowToken::headless(),
            scale: 1.,
        };
        app.overlay = Some(overlay());
        frame(&mut app, &ctx, 0., vec![]);
        frame(
            &mut app,
            &ctx,
            0.1,
            vec![
                Event::PointerMoved(pos2(40., 50.)),
                pointer(pos2(40., 50.), true),
            ],
        );
        frame(
            &mut app,
            &ctx,
            0.2,
            vec![Event::PointerMoved(pos2(210., 180.))],
        );
        frame(&mut app, &ctx, 0.3, vec![pointer(pos2(210., 180.), false)]);
        assert!(app.overlay.is_none());
        assert_eq!((app.doc.width, app.doc.height), (170, 130));
        assert_eq!(app.doc.background.get_pixel(0, 0).0, [40, 50, 17, 255]);
        let last = app.last_area.unwrap();
        assert_eq!(
            (last.x, last.y, last.width, last.height),
            (-1160, 70, 170, 130)
        );
        let accepted = app.doc.background.clone();
        app.overlay = Some(overlay());
        frame(&mut app, &ctx, 0.4, vec![]);
        frame(
            &mut app,
            &ctx,
            0.5,
            vec![Event::Key {
                key: Key::Escape,
                physical_key: None,
                pressed: true,
                repeat: false,
                modifiers: Modifiers::NONE,
            }],
        );
        assert!(app.overlay.is_none());
        assert!(Arc::ptr_eq(&accepted, &app.doc.background));
    }

    #[test]
    fn pointer_drag_creates_one_arrow_and_undo_redo_restore_it() {
        let ctx = Context::default();
        let root =
            std::env::temp_dir().join(format!("capture-rust-ui-test-{}", std::process::id()));
        let mut app = CaptureApp::new(&ctx, root);
        for i in 0..5 {
            frame(&mut app, &ctx, i as f64 / 60., vec![]);
        }
        app.execute(&ctx, Command::Tool(Tool::Arrow));
        frame(
            &mut app,
            &ctx,
            0.1,
            vec![
                Event::PointerMoved(pos2(200., 300.)),
                pointer(pos2(200., 300.), true),
            ],
        );
        frame(
            &mut app,
            &ctx,
            0.2,
            vec![Event::PointerMoved(pos2(250., 330.))],
        );
        frame(
            &mut app,
            &ctx,
            0.3,
            vec![Event::PointerMoved(pos2(400., 400.))],
        );
        frame(&mut app, &ctx, 0.4, vec![pointer(pos2(400., 400.), false)]);
        assert_eq!(app.doc.forms.len(), 1);
        assert_eq!(app.doc.forms[0].tool, Tool::Arrow);
        assert!(app.doc.forms[0].rect().width() > 200.);
        assert!(app.dirty);
        let points = app.doc.forms[0].points.clone();
        app.execute(&ctx, Command::Undo);
        assert!(app.doc.forms.is_empty());
        app.execute(&ctx, Command::Redo);
        assert_eq!(app.doc.forms[0].points, points);
    }

    #[test]
    fn lens_keyboard_navigation_and_search_execute_the_selected_command() {
        let ctx = Context::default();
        let mut app = CaptureApp::new(
            &ctx,
            std::env::temp_dir().join("capture-lens-keyboard-test"),
        );
        let key = |key| Event::Key {
            key,
            physical_key: None,
            pressed: true,
            repeat: false,
            modifiers: Modifiers::NONE,
        };
        frame(&mut app, &ctx, 0., vec![]);
        app.execute(&ctx, Command::Lens);
        frame(&mut app, &ctx, 0.1, vec![]);
        let initial = app.lens_index;
        frame(&mut app, &ctx, 0.2, vec![key(Key::ArrowDown)]);
        assert_ne!(app.lens_index, initial);
        frame(&mut app, &ctx, 0.3, vec![key(Key::ArrowUp)]);
        assert_eq!(app.lens_index, initial);
        app.lens_query = "line".into();
        frame(&mut app, &ctx, 0.4, vec![]);
        frame(&mut app, &ctx, 0.5, vec![key(Key::Enter)]);
        assert!(!app.lens);
        assert_eq!(app.tool, Tool::Line);
    }

    #[test]
    fn selection_commands_share_history_and_group_identity() {
        let ctx = Context::default();
        let mut app = CaptureApp::new(
            &ctx,
            std::env::temp_dir().join("capture-rust-command-tests"),
        );
        app.doc
            .create(Tool::Shape, pos2(10., 10.), Style::default());
        app.doc
            .create(Tool::Shape, pos2(100., 100.), Style::default());
        app.execute(&ctx, Command::SelectAll);
        app.execute(&ctx, Command::Group);
        assert_eq!(app.doc.forms[0].groups, app.doc.forms[1].groups);
        app.execute(&ctx, Command::Duplicate);
        assert_eq!(app.doc.forms.len(), 4);
        assert_ne!(app.doc.forms[0].groups, app.doc.forms[2].groups);
        app.execute(&ctx, Command::Delete);
        assert_eq!(app.doc.forms.len(), 2);
        app.execute(&ctx, Command::Undo);
        assert_eq!(app.doc.forms.len(), 4);
    }
}

fn draw_glyph(p: &Painter, r: Rect, tool: Tool, color: Color32) {
    let stroke = Stroke::new(1.4_f32, color);
    let c = r.center();
    match tool {
        Tool::Select => {
            p.add(Shape::closed_line(
                vec![r.min, c + vec2(5., 0.), c, c + vec2(0., 6.)],
                stroke,
            ));
        }
        Tool::Shape => {
            p.circle_stroke(c - vec2(3., 2.), 4., stroke);
            p.rect_stroke(
                Rect::from_center_size(c + vec2(3., 3.), vec2(8., 8.)),
                2,
                stroke,
                StrokeKind::Middle,
            );
        }
        Tool::Polygon => {
            p.add(Shape::closed_line(
                vec![r.center_top(), r.right_bottom(), r.left_bottom()],
                stroke,
            ));
        }
        Tool::Arrow => {
            p.arrow(
                vec2(1., -1.).to_pos2() + r.left_bottom().to_vec2(),
                vec2(r.width() - 2., -r.height() + 2.),
                stroke,
            );
        }
        Tool::Line => {
            p.line_segment([r.left_bottom(), r.right_top()], stroke);
        }
        Tool::Text => {
            p.text(
                c,
                Align2::CENTER_CENTER,
                "T",
                FontId::proportional(17.),
                color,
            );
        }
        Tool::Callout => {
            p.rect_stroke(r.shrink2(vec2(1., 3.)), 3, stroke, StrokeKind::Middle);
            p.line_segment(
                [
                    r.left_bottom() + vec2(4., -3.),
                    r.left_bottom() + vec2(2., 1.),
                ],
                stroke,
            );
        }
        Tool::Draw | Tool::Highlight => {
            p.add(Shape::line(
                vec![
                    r.left_bottom(),
                    c - vec2(3., 0.),
                    c + vec2(2., 2.),
                    r.right_top(),
                ],
                stroke,
            ));
        }
        Tool::Step => {
            p.circle_stroke(c, 6., stroke);
            p.text(c, Align2::CENTER_CENTER, "1", FontId::monospace(9.), color);
        }
        Tool::Image => {
            p.rect_stroke(r.shrink(1.), 2, stroke, StrokeKind::Middle);
            p.add(Shape::line(
                vec![
                    r.left_bottom() - vec2(-2., 3.),
                    c,
                    r.right_bottom() - vec2(2., 3.),
                ],
                stroke,
            ));
        }
        Tool::PixelSelection => {
            p.rect_stroke(r.shrink(1.), 0, stroke, StrokeKind::Middle);
        }
    }
}
