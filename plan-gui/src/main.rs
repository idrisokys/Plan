//! Plan / Notlarım — egui arayüzü. Tüm mantık `plan-core`'dadır; burası yalnızca görünüm.
//!
//! NOT: Bu crate ağ erişimi olan bir makinede derlenmek üzere yazıldı (eframe/egui 0.29, tray-icon 0.19,
//! mdns-sd 0.11). Çekirdek ve CLI çevrimdışı derlenip test edildi; bu dosya henüz derlenmedi.

mod share;

use eframe::egui::{self, Color32, Key, Modifiers, RichText};
use plan_core::config::{self, Settings};
use plan_core::engines::{self, SearchEngine, UrlAction};
use plan_core::quickshare::{self, Event, ServerConfig};
use plan_core::store::{self, SubmitResult};
use plan_core::sync::{self, Outcome, Peer};
use plan_core::text::l;
use plan_core::{reorder, search, Entry, Hit};
use std::collections::HashSet;
use std::path::PathBuf;
use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::{
    atomic::{AtomicU64, Ordering},
    Arc,
};
use std::time::{Duration, Instant};

const BG: Color32 = Color32::from_rgb(33, 33, 33);
const BLUE: Color32 = Color32::from_rgb(140, 204, 255);
const PIN_RED: Color32 = Color32::from_rgb(160, 30, 30);

enum Msg {
    Reload,
    Toast(String),
    Search(u64, Vec<Hit>),
    Qs(Event),
    Devices,
    SyncDone(Outcome),
    Tray(TrayCmd),
    External(String),
}

#[derive(Debug, Clone, Copy)]
enum TrayCmd {
    Notes,
    SaveLocation,
    OpenFolder,
    Quit,
}

enum View {
    List,
    Txt { entry: Entry, saved: String, draft: String, editing: bool, query: String, cur: usize },
}

struct App {
    tx: Sender<Msg>,
    rx: Receiver<Msg>,
    settings: Settings,
    engines: Vec<SearchEngine>,
    root: Option<PathBuf>,
    stack: Vec<Entry>,
    list: Vec<Entry>,
    view: View,
    input: String,
    edit_mode: bool,
    selected: HashSet<String>,
    renaming: Option<(Entry, String)>,
    searching: Option<(String, Option<Vec<Hit>>)>,
    search_gen: Arc<AtomicU64>,
    toast: Option<(String, Instant)>,
    share: share::Share,
    show_share: bool,
    sync_picked: HashSet<String>,
    sync_mode: i32,
    syncing: bool,
    qs_info: Option<(String, Option<PathBuf>)>,
    moving: Option<Vec<Entry>>,
    share_files: Vec<PathBuf>,
    new_folder: Option<String>,
    quit: bool,
    _tray: Option<tray_icon::TrayIcon>,
}

impl App {
    fn new(cc: &eframe::CreationContext<'_>) -> App {
        let (tx, rx) = channel();
        let mut settings = Settings::load();
        let my_id = settings.qs_id();
        let ctx = cc.egui_ctx.clone();
        ctx.set_visuals(egui::Visuals::dark());
        let mut app = App {
            tx: tx.clone(),
            rx,
            engines: engines::load_engines(&config::config_dir().join("engines.tsv")),
            root: store::root(),
            stack: vec![],
            list: vec![],
            view: View::List,
            input: String::new(),
            edit_mode: false,
            selected: HashSet::new(),
            renaming: None,
            searching: None,
            search_gen: Arc::new(AtomicU64::new(0)),
            toast: None,
            share: share::Share::new(my_id),
            show_share: false,
            sync_picked: HashSet::new(),
            sync_mode: 0,
            syncing: false,
            qs_info: None,
            moving: None,
            share_files: vec![],
            new_folder: None,
            quit: false,
            _tray: None,
            settings,
        };
        app.setup_tray(&ctx);
        if app.settings.always_on_top() {
            ctx.send_viewport_cmd(egui::ViewportCommand::WindowLevel(egui::WindowLevel::AlwaysOnTop));
        }
        if app.settings.qs_on() {
            app.start_share(&ctx);
        }
        // Komut satırından gelen plan:// adresi
        if let Some(u) = std::env::args().nth(1).filter(|a| a.starts_with("plan://")) {
            let _ = tx.send(Msg::External(u));
        }
        app.reload();
        app
    }

    // ---------- Sistem tepsisi ----------
    fn setup_tray(&mut self, ctx: &egui::Context) {
        use tray_icon::menu::{Menu, MenuEvent, MenuItem, PredefinedMenuItem};
        let menu = Menu::new();
        let items = [
            (TrayCmd::Notes, l("Notlarım", "My Notes")),
            (TrayCmd::SaveLocation, l("Kayıt yeri…", "Save location…")),
            (TrayCmd::OpenFolder, l("Notlarım klasörü", "Notes folder")),
        ];
        let mut ids = vec![];
        for (cmd, label) in items {
            let it = MenuItem::new(label, true, None);
            let _ = menu.append(&it);
            ids.push((it.id().clone(), cmd));
        }
        let _ = menu.append(&PredefinedMenuItem::separator());
        let quit = MenuItem::new(l("Çık", "Quit"), true, None);
        let _ = menu.append(&quit);
        ids.push((quit.id().clone(), TrayCmd::Quit));

        let tx = self.tx.clone();
        let c2 = ctx.clone();
        MenuEvent::set_event_handler(Some(move |e: MenuEvent| {
            if let Some((_, cmd)) = ids.iter().find(|(id, _)| *id == e.id) {
                let _ = tx.send(Msg::Tray(*cmd));
                c2.request_repaint();
            }
        }));
        // Simge: gömülü PNG (Resources/MenuIcon.png)
        let icon = image::load_from_memory(include_bytes!("../../assets/MenuIcon.png"))
            .ok()
            .and_then(|i| {
                let r = i.to_rgba8();
                let (w, h) = r.dimensions();
                tray_icon::Icon::from_rgba(r.into_raw(), w, h).ok()
            });
        let mut b = tray_icon::TrayIconBuilder::new().with_menu(Box::new(menu)).with_tooltip("Plan");
        if let Some(i) = icon {
            b = b.with_icon(i);
        }
        self._tray = b.build().ok();
    }

    // ---------- Yardımcılar ----------
    fn current(&self) -> Option<PathBuf> {
        self.stack.last().map(|e| e.path.clone()).or_else(|| self.root.clone())
    }

    fn toast(&mut self, s: impl Into<String>) {
        self.toast = Some((s.into(), Instant::now()));
    }

    fn bg<F: FnOnce(Sender<Msg>) + Send + 'static>(&self, ctx: &egui::Context, f: F) {
        let tx = self.tx.clone();
        let ctx = ctx.clone();
        std::thread::spawn(move || {
            f(tx);
            ctx.request_repaint();
        });
    }

    fn reload(&mut self) {
        self.list = self.current().map(|d| store::list(&d)).unwrap_or_default();
        self.selected.retain(|k| self.list.iter().any(|e| &e.key == k));
    }

    fn open_external(target: &str) {
        let (prog, args): (&str, Vec<&str>) = if cfg!(target_os = "macos") {
            ("open", vec![target])
        } else if cfg!(windows) {
            ("cmd", vec!["/C", "start", "", target])
        } else {
            ("xdg-open", vec![target])
        };
        let _ = std::process::Command::new(prog).args(args).spawn();
    }

    fn submit(&mut self, ctx: &egui::Context, text: String, subject: Option<String>) {
        let Some(dir) = self.current() else { return };
        self.bg(ctx, move |tx| {
            let m = match store::submit(&dir, &text, subject.as_deref()) {
                SubmitResult::Added => l("Eklendi", "Added"),
                SubmitResult::TextFile => l("Metin dosyası eklendi", "Text file added"),
                SubmitResult::Failed => l("Kaydedilemedi", "Couldn't save"),
            };
            let _ = tx.send(Msg::Toast(m));
            let _ = tx.send(Msg::Reload);
        });
    }

    fn run_search(&mut self, ctx: &egui::Context, q: String) {
        let Some(root) = self.root.clone() else { return };
        let gen = self.search_gen.fetch_add(1, Ordering::SeqCst) + 1;
        self.searching = Some((q.clone(), None));
        let flag = self.search_gen.clone();
        self.bg(ctx, move |tx| {
            let hits = search::search(&root, &q, &|| flag.load(Ordering::SeqCst) == gen);
            if flag.load(Ordering::SeqCst) == gen {
                let _ = tx.send(Msg::Search(gen, hits));
            }
        });
    }

    fn start_share(&mut self, ctx: &egui::Context) {
        let Some(root) = self.root.clone() else { return };
        let (tx, c2) = (self.tx.clone(), ctx.clone());
        let (tx2, c3) = (self.tx.clone(), ctx.clone());
        let (dtx, drx) = channel::<()>();
        std::thread::spawn(move || {
            while drx.recv().is_ok() {
                let _ = tx2.send(Msg::Devices);
                c3.request_repaint();
            }
        });
        let cfg = ServerConfig { root, receive_dir: self.settings.receive_dir(), trash_dir: store::onemsiz_dir() };
        let res = self.share.start(
            cfg,
            Arc::new(move |e| {
                let _ = tx.send(Msg::Qs(e));
                c2.request_repaint();
            }),
            dtx,
        );
        match res {
            Ok(()) => self.settings.set_qs_on(true),
            Err(e) => self.toast(format!("{}: {e}", l("Paylaşım açılamadı", "Couldn't start sharing"))),
        }
    }

    fn stop_share(&mut self) {
        self.share.stop();
        self.settings.set_qs_on(false);
        self.qs_info = None;
    }

    fn handle_msgs(&mut self, ctx: &egui::Context) {
        while let Ok(m) = self.rx.try_recv() {
            match m {
                Msg::Reload => self.reload(),
                Msg::Toast(s) => self.toast(s),
                Msg::Search(g, h) => {
                    if g == self.search_gen.load(Ordering::SeqCst) {
                        if let Some((_, slot)) = &mut self.searching {
                            *slot = Some(h);
                        }
                    }
                }
                Msg::Qs(e) => match e {
                    Event::Receiving(n) => self.qs_info = Some((format!("{} {n}", l("Alınıyor:", "Receiving:")), None)),
                    Event::Received { name, folder } => self.qs_info = Some((format!("{} {name}", l("Alındı:", "Received:")), Some(folder))),
                    Event::Failed(m) => self.qs_info = Some((m, None)),
                    Event::NotesChanged => self.reload(),
                },
                Msg::Devices => {}
                Msg::SyncDone(o) => {
                    self.syncing = false;
                    self.qs_info = Some((o.message(), None));
                    self.reload();
                }
                Msg::External(u) => match engines::parse_plan_url(&u) {
                    Some(UrlAction::Add { text, subject }) => self.submit(ctx, text, subject),
                    Some(UrlAction::Search(q)) => {
                        self.stack.clear();
                        self.reload();
                        self.input = q.clone();
                        self.run_search(ctx, q);
                    }
                    _ => {}
                },
                Msg::Tray(c) => match c {
                    TrayCmd::Notes => {
                        ctx.send_viewport_cmd(egui::ViewportCommand::Visible(true));
                        ctx.send_viewport_cmd(egui::ViewportCommand::Focus);
                    }
                    TrayCmd::SaveLocation => {
                        if let Some(p) = rfd::FileDialog::new().set_directory(self.settings.receive_dir()).pick_folder() {
                            self.settings.set_receive_dir(&p);
                            if self.share.running() {
                                self.stop_share();
                                self.start_share(ctx);
                            }
                        }
                    }
                    TrayCmd::OpenFolder => {
                        if let Some(r) = &self.root {
                            Self::open_external(&r.to_string_lossy());
                        }
                    }
                    TrayCmd::Quit => self.quit = true,
                },
            }
        }
    }

    // ---------- Satır işlemleri ----------
    fn tap(&mut self, ctx: &egui::Context, e: &Entry) {
        if self.edit_mode {
            if !self.selected.remove(&e.key) {
                self.selected.insert(e.key.clone());
            }
            self.sync_rename();
        } else if e.is_dir {
            self.stack.push(e.clone());
            self.selected.clear();
            self.reload();
        } else if e.is_txt {
            match store::read_plain(&e.path) {
                Some(t) => self.view = View::Txt { entry: e.clone(), saved: t.clone(), draft: t, editing: false, query: String::new(), cur: 0 },
                None => self.toast(l("Dosya okunamadı", "Couldn't read the file")),
            }
        } else {
            let (u, t) = store::read_link(&e.path);
            if let Some(u) = u {
                let scheme = u.split(':').next().unwrap_or("").to_lowercase();
                // Yerel dosya / betik çalıştıran şemalar açılmaz
                if scheme == "file" || scheme == "javascript" {
                    self.toast(l("Link açılamadı", "Couldn't open the link"));
                } else {
                    Self::open_external(&u);
                }
            } else if let Some(t) = t {
                ctx.copy_text(t);
                self.toast(l("Kopyalandı", "Copied"));
            } else {
                self.toast(l("Link okunamadı", "Couldn't read the link"));
            }
        }
    }

    fn sync_rename(&mut self) {
        self.renaming = if self.edit_mode && self.selected.len() == 1 {
            self.list.iter().find(|e| self.selected.contains(&e.key)).map(|e| (e.clone(), e.title.clone()))
        } else {
            None
        };
    }

    fn copy_entry(&mut self, ctx: &egui::Context, e: &Entry) {
        let t = if e.is_dir {
            Some(e.title.clone())
        } else if e.is_txt {
            store::read_plain(&e.path)
        } else {
            let (u, n) = store::read_link(&e.path);
            Some(u.or(n).unwrap_or_else(|| e.title.clone()))
        };
        match t {
            Some(t) => {
                ctx.copy_text(t);
                self.toast(l("Kopyalandı", "Copied"));
            }
            None => self.toast(l("Kopyalanamadı", "Couldn't copy")),
        }
    }

    fn trash(&mut self, items: Vec<Entry>) {
        let n = items.iter().filter(|e| store::trash(&e.path)).count();
        self.selected.clear();
        self.reload();
        let total = items.len();
        self.toast(if n == total {
            l(&format!(".onemsiz klasörüne taşındı ({n})"), &format!("Moved to .onemsiz ({n})"))
        } else {
            l(&format!("{n}/{total} öğe .onemsiz'e taşınabildi"), &format!("{n}/{total} items moved to .onemsiz"))
        });
    }

    fn toggle_pin(&mut self, items: &[Entry]) {
        let Some(dir) = self.current() else { return };
        let pin = !items.iter().all(|e| e.pinned);
        let names: Vec<String> = items.iter().map(|e| e.name.clone()).collect();
        store::set_pinned(&dir, &names, pin);
        self.selected.clear();
        self.reload();
    }

    fn move_sel(&mut self, mode: i32) {
        let Some(dir) = self.current() else { return };
        if reorder::move_selected(&mut self.list, &self.selected, mode) {
            let names: Vec<String> = self.list.iter().map(|e| e.name.clone()).collect();
            store::save_order(&dir, &names);
        }
    }

    fn save_rename(&mut self) {
        let Some((e, text)) = self.renaming.take() else { return };
        let Some(dir) = self.current() else { return };
        if text.trim().is_empty() {
            return;
        }
        let to_txt = !e.is_dir && !e.is_txt && text.trim().chars().count() > 116;
        let ok = if to_txt {
            let mut body = text.trim().to_string();
            if let (Some(u), _) = store::read_link(&e.path) {
                body.push('\n');
                body.push_str(&u);
            }
            store::convert_to_txt(&dir, &e, &body)
        } else {
            store::rename(&dir, &e, &text)
        };
        self.edit_mode = false;
        self.selected.clear();
        self.reload();
        if !ok {
            self.toast(l("Ad değiştirilemedi (aynı adda öğe olabilir)", "Couldn't rename (an item with that name may exist)"));
        } else if to_txt {
            self.toast(l("Uzun olduğu için .txt olarak kaydedildi", "Too long, saved as .txt"));
        }
    }

    // ---------- Çizim ----------
    fn ui_top(&mut self, ui: &mut egui::Ui, ctx: &egui::Context) {
        ui.horizontal(|ui| {
            if (!self.stack.is_empty() || self.searching.is_some() || matches!(self.view, View::Txt { .. })) && ui.button("◀").clicked() {
                self.go_back();
            }
            let title = if let Some((q, h)) = &self.searching {
                format!("“{q}”{}", h.as_ref().map(|h| format!(" · {} {}", h.len(), l("sonuç", "results"))).unwrap_or_default())
            } else if self.edit_mode && !self.selected.is_empty() {
                format!("{} {}", self.selected.len(), l("seçili", "selected"))
            } else {
                self.stack.last().map(|e| e.title.clone()).unwrap_or_else(|| "Notlarım".into())
            };
            ui.label(RichText::new(title).strong());
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                let mut top = self.settings.always_on_top();
                if ui.toggle_value(&mut top, "📌").on_hover_text(l("Her zaman üstte", "Always on top")).changed() {
                    self.settings.set_always_on_top(top);
                    ctx.send_viewport_cmd(egui::ViewportCommand::WindowLevel(if top {
                        egui::WindowLevel::AlwaysOnTop
                    } else {
                        egui::WindowLevel::Normal
                    }));
                }
                let qs = self.share.running();
                if ui.selectable_label(qs, RichText::new("📡").color(if qs { BLUE } else { Color32::GRAY })).on_hover_text(l("Hızlı Paylaş", "Quick Share")).clicked() {
                    if qs {
                        self.stop_share();
                    } else {
                        self.start_share(ctx);
                    }
                }
                if qs && ui.button("⇄").on_hover_text(l("Eşitle", "Sync")).clicked() {
                    self.show_share = !self.show_share;
                }
                if ui.button("⟳").on_hover_text(l("Yenile", "Refresh")).clicked() {
                    self.root = store::root();
                    self.reload();
                    if let Some((q, _)) = self.searching.clone() {
                        self.run_search(ctx, q);
                    }
                }
                if ui.button("🗁+").on_hover_text(l("Klasör ekle", "Add folder")).clicked() {
                    self.new_folder = Some(String::new());
                }
                if ui.button("A+").clicked() {
                    self.settings.bump_font(2.0);
                }
                if ui.button("A−").clicked() {
                    self.settings.bump_font(-2.0);
                }
            });
        });
    }

    fn go_back(&mut self) {
        if let View::Txt { saved, draft, editing, .. } = &mut self.view {
            if *editing && draft != saved {
                // kaydedilmemiş değişiklik: onay yerine taslağı atmadan önce uyar
                *draft = saved.clone();
                *editing = false;
                self.toast(l("Değişiklikler atıldı", "Changes discarded"));
                return;
            }
            if *editing {
                *editing = false;
                return;
            }
            self.view = View::List;
        } else if self.searching.is_some() {
            self.search_gen.fetch_add(1, Ordering::SeqCst);
            self.searching = None;
        } else if self.edit_mode {
            self.edit_mode = false;
            self.selected.clear();
            self.renaming = None;
        } else if !self.stack.is_empty() {
            self.stack.pop();
            self.selected.clear();
            self.reload();
        }
    }

    fn ui_list(&mut self, ui: &mut egui::Ui, ctx: &egui::Context) {
        let fs = self.settings.font_size() as f32;
        let mut tapped: Option<Entry> = None;
        let mut copy: Option<Entry> = None;
        let mut act: Option<(&'static str, Entry)> = None;
        egui::ScrollArea::vertical().auto_shrink([false, false]).show(ui, |ui| {
            if let Some((_, Some(hits))) = &self.searching {
                for h in hits {
                    let path = h.path.iter().map(|e| e.title.as_str()).collect::<Vec<_>>().join(" › ");
                    ui.vertical(|ui| {
                        if ui.add(egui::Label::new(RichText::new(&h.entry.title).size(fs)).sense(egui::Sense::click())).clicked() {
                            tapped = Some(h.entry.clone());
                        }
                        if !path.is_empty() {
                            ui.label(RichText::new(path).small().color(Color32::GRAY));
                        }
                        ui.label(RichText::new(&h.detail).small().color(Color32::GRAY));
                    });
                    ui.separator();
                }
                return;
            }
            for e in &self.list {
                let sel = self.selected.contains(&e.key);
                ui.horizontal(|ui| {
                    let icon = if e.is_dir { "📁" } else if e.is_txt { "📄" } else { "🔗" };
                    let r = ui.add(egui::SelectableLabel::new(sel, RichText::new(format!("{icon}  {}", e.title)).size(fs)));
                    if r.clicked() {
                        tapped = Some(e.clone());
                    }
                    if r.secondary_clicked() || r.long_touched() {
                        copy = Some(e.clone());
                    }
                    ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                        ui.menu_button(RichText::new("⋮").color(if e.pinned { PIN_RED } else { Color32::GRAY }), |ui| {
                            for (id, label) in [
                                ("pin", if e.pinned { l("Sabitlemeyi kaldır", "Unpin") } else { l("Sabitle", "Pin") }),
                                ("edit", l("Düzenle", "Edit")),
                                ("move", l("Taşı", "Move")),
                                ("share", l("Paylaş", "Share")),
                                ("delete", l("Sil", "Delete")),
                            ] {
                                if ui.button(label).clicked() {
                                    act = Some((id, e.clone()));
                                    ui.close_menu();
                                }
                            }
                        });
                    });
                });
            }
            if self.list.is_empty() {
                ui.add_space(40.0);
                ui.vertical_centered(|ui| ui.label(RichText::new(l("Henüz not yok", "No notes yet")).color(Color32::GRAY)));
            }
        });
        if let Some(e) = tapped {
            if self.searching.is_some() && !e.is_dir {
                self.searching = None;
            }
            self.tap(ctx, &e);
        }
        if let Some(e) = copy {
            self.copy_entry(ctx, &e);
        }
        if let Some((id, e)) = act {
            match id {
                "pin" => self.toggle_pin(&[e]),
                "edit" => {
                    self.renaming = Some((e.clone(), e.title.clone()));
                }
                "move" => self.moving = Some(vec![e]),
                "share" => {
                    if e.is_dir {
                        self.toast(l("Klasörler paylaşılamaz", "Folders cannot be shared"));
                    } else {
                        self.show_share = true;
                        self.share_files = vec![e.path.clone()];
                    }
                }
                "delete" => self.trash(vec![e]),
                _ => {}
            }
        }
    }

    fn ui_bottom(&mut self, ui: &mut egui::Ui, ctx: &egui::Context) {
        // Yeniden adlandırma çubuğu
        if self.renaming.is_some() {
            let mut do_save = false;
            if let Some((e, text)) = &mut self.renaming {
                let cap = if !e.is_dir && !e.is_txt { 20_000 } else { 116 };
                ui.horizontal(|ui| {
                    ui.label(l("Ad:", "Name:"));
                    ui.add(egui::TextEdit::singleline(text).desired_width(f32::INFINITY));
                });
                if text.chars().count() > cap {
                    *text = text.chars().take(cap).collect();
                }
                do_save = ui.button(l("Kaydet", "Save")).clicked();
            }
            if do_save {
                self.save_rename();
            }
            return;
        }
        let id = egui::Id::new("add_input");
        let focused = ctx.memory(|m| m.has_focus(id));
        let enter = focused && ctx.input_mut(|i| i.consume_key(Modifiers::NONE, Key::Enter));
        let count = self.input.chars().count();
        ui.add(
            egui::TextEdit::multiline(&mut self.input)
                .id(id)
                .desired_rows(2)
                .desired_width(f32::INFINITY)
                .hint_text(l("Ara; Enter ile ekle", "Search; Enter to add")),
        );
        ui.horizontal(|ui| {
            ui.label(RichText::new(format!("{count}/{}", store::ADD_MAX)).small().color(Color32::GRAY));
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                if ui.button("✕").on_hover_text(l("Temizle", "Clear")).clicked() {
                    self.input.clear();
                    self.search_gen.fetch_add(1, Ordering::SeqCst);
                    self.searching = None;
                }
                if ui.button("🔍").on_hover_text(l("Ara", "Search")).clicked() && !self.input.trim().is_empty() {
                    let q = self.input.trim().to_string();
                    self.run_search(ctx, q);
                }
                let m = if self.edit_mode { "✎" } else { "○" };
                if ui.selectable_label(self.edit_mode, m).on_hover_text(l("Düzenle / seç / sırala", "Edit / select / reorder")).clicked() {
                    self.edit_mode = !self.edit_mode;
                    self.selected.clear();
                    self.renaming = None;
                }
                if self.edit_mode && !self.selected.is_empty() {
                    if ui.button("🗑").clicked() {
                        let items: Vec<Entry> = self.list.iter().filter(|e| self.selected.contains(&e.key)).cloned().collect();
                        self.trash(items);
                    }
                    let (up, down) = (reorder::can_move_up(&self.list, &self.selected), reorder::can_move_down(&self.list, &self.selected));
                    for (label, mode, en) in [("⤓", 2, down), ("↓", 1, down), ("↑", -1, up), ("⤒", -2, up)] {
                        if ui.add_enabled(en, egui::Button::new(label)).clicked() {
                            self.move_sel(mode);
                        }
                    }
                }
            });
        });
        if enter {
            let t = self.input.trim().to_string();
            if !t.is_empty() {
                self.input.clear();
                self.submit(ctx, t, None);
            }
        }
        // Yazdıkça canlı arama (panel davranışı)
        // (isteğe bağlı: burada self.run_search çağrılabilir; maliyet nedeniyle düğmeye bırakıldı)
    }

    fn ui_txt(&mut self, ui: &mut egui::Ui) {
        let fs = self.settings.font_size() as f32;
        let mut save = false;
        let View::Txt { entry, saved, draft, editing, query, cur } = &mut self.view else { return };
        ui.horizontal(|ui| {
            ui.label(RichText::new(&entry.title).strong());
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                if *editing {
                    if ui.button(l("Kaydet", "Save")).clicked() {
                        save = true;
                    }
                } else if ui.button("✎").clicked() {
                    *draft = saved.clone();
                    *editing = true;
                }
            });
        });
        if *editing {
            egui::ScrollArea::vertical().show(ui, |ui| {
                ui.add(egui::TextEdit::multiline(draft).font(egui::FontId::proportional(fs)).desired_width(f32::INFINITY).desired_rows(20));
            });
        } else {
            ui.horizontal(|ui| {
                ui.label("🔍");
                ui.add(egui::TextEdit::singleline(query).desired_width(160.0));
                let m = search::txt_matches(saved, query);
                if !m.is_empty() {
                    if *cur >= m.len() {
                        *cur = 0;
                    }
                    ui.label(format!("{}/{}", *cur + 1, m.len()));
                    if ui.button("▲").clicked() {
                        *cur = (*cur + m.len() - 1) % m.len();
                    }
                    if ui.button("▼").clicked() {
                        *cur = (*cur + 1) % m.len();
                    }
                }
            });
            let matches = search::txt_matches(saved, query);
            egui::ScrollArea::vertical().show(ui, |ui| {
                if matches.is_empty() {
                    ui.label(RichText::new(saved.as_str()).size(fs));
                } else {
                    // Eşleşmeleri işaretleyerek göster (karakter konumlarına göre)
                    let chars: Vec<char> = saved.chars().collect();
                    let mut job = egui::text::LayoutJob::default();
                    let normal = egui::TextFormat { font_id: egui::FontId::proportional(fs), ..Default::default() };
                    let mut pos = 0;
                    for (i, (s, e)) in matches.iter().enumerate() {
                        job.append(&chars[pos..*s].iter().collect::<String>(), 0.0, normal.clone());
                        let mut f = normal.clone();
                        f.background = if i == *cur { Color32::from_rgb(200, 140, 0) } else { Color32::from_rgb(90, 90, 20) };
                        job.append(&chars[*s..*e].iter().collect::<String>(), 0.0, f);
                        pos = *e;
                    }
                    job.append(&chars[pos..].iter().collect::<String>(), 0.0, normal);
                    ui.label(job);
                }
            });
        }
        let mut failed = false;
        if save {
            let (e, t) = (entry.clone(), draft.clone());
            if store::write_plain(&e.path, &t) {
                *saved = t;
                *editing = false;
            } else {
                failed = true;
            }
        }
        if failed {
            self.toast(l("Kaydedilemedi", "Couldn't save"));
        }
    }

    fn ui_share_window(&mut self, ctx: &egui::Context) {
        if !self.show_share {
            return;
        }
        let mut open = true;
        egui::Window::new(l("Hızlı Paylaş", "Quick Share")).open(&mut open).default_width(300.0).show(ctx, |ui| {
            if !self.share.running() {
                if ui.button(l("Aç", "Turn on")).clicked() {
                    self.start_share(ctx);
                }
                return;
            }
            if let Some((t, folder)) = self.qs_info.clone() {
                if ui.link(&t).clicked() {
                    if let Some(f) = folder {
                        Self::open_external(&f.to_string_lossy());
                    }
                }
            }
            let devices: Vec<Peer> = self.share.devices.lock().unwrap().clone();
            if devices.is_empty() {
                ui.label(RichText::new(l("Açık cihaz yok", "No open devices")).color(Color32::GRAY));
            }
            for d in &devices {
                ui.horizontal(|ui| {
                    let mut on = self.sync_picked.contains(&d.id);
                    if ui.checkbox(&mut on, &d.name).changed() {
                        if on { self.sync_picked.insert(d.id.clone()); } else { self.sync_picked.remove(&d.id); }
                    }
                    if ui.button("🗁").on_hover_text(l("Dosya gönder", "Send files")).clicked() {
                        let files = if self.share_files.is_empty() { rfd::FileDialog::new().pick_files().unwrap_or_default() } else { std::mem::take(&mut self.share_files) };
                        if !files.is_empty() {
                            let addr = d.addr.clone();
                            let name = d.name.clone();
                            self.bg(ctx, move |tx| {
                                let n = quickshare::send_files(&files, &addr);
                                let m = if n == files.len() {
                                    l(&format!("Gönderildi → {name}"), &format!("Sent → {name}"))
                                } else {
                                    l(&format!("Gönderilemedi ({} dosya) → {name}", files.len() - n), &format!("Failed ({} files) → {name}", files.len() - n))
                                };
                                let _ = tx.send(Msg::Toast(m));
                            });
                        }
                    }
                });
            }
            ui.separator();
            ui.label(l("Link klasörünü eşitle", "Sync the Link folder"));
            ui.radio_value(&mut self.sync_mode, 0, l("İki cihazda aynı olsun", "Same on both"));
            ui.radio_value(&mut self.sync_mode, 1, l("Bu cihaza göre", "Follow this device"));
            ui.radio_value(&mut self.sync_mode, 2, l("Karşıdaki cihaza göre", "Follow the other device"));
            let picked: Vec<Peer> = devices.into_iter().filter(|d| self.sync_picked.contains(&d.id)).collect();
            if ui.add_enabled(!self.syncing && !picked.is_empty(), egui::Button::new(if self.syncing { l("Eşitleniyor…", "Syncing…") } else { l("Eşitle", "Sync") })).clicked() {
                if let Some(root) = self.root.clone() {
                    self.syncing = true;
                    let mode = self.sync_mode;
                    self.bg(ctx, move |tx| {
                        let o = sync::run(mode, &picked, &root, &store::onemsiz_dir());
                        let _ = tx.send(Msg::SyncDone(o));
                    });
                }
            }
        });
        self.show_share = open;
    }

    fn ui_dialogs(&mut self, ctx: &egui::Context) {
        if let Some(name) = &mut self.new_folder {
            let mut done = None;
            egui::Window::new(l("Yeni klasör", "New folder")).collapsible(false).show(ctx, |ui| {
                ui.text_edit_singleline(name);
                ui.horizontal(|ui| {
                    if ui.button(l("Ekle", "Add")).clicked() { done = Some(true); }
                    if ui.button(l("İptal", "Cancel")).clicked() { done = Some(false); }
                });
            });
            if let Some(ok) = done {
                let n = name.trim().to_string();
                self.new_folder = None;
                if ok && !n.is_empty() {
                    if let Some(d) = self.current() { store::add_folder(&d, &n); }
                    self.reload();
                }
            }
        }
        if let Some(items) = self.moving.clone() {
            let mut close = false;
            egui::Window::new(l("Taşı", "Move")).collapsible(false).show(ctx, |ui| {
                let Some(root) = self.root.clone() else { return };
                let mut targets: Vec<(String, PathBuf)> = vec![("/".into(), root.clone())];
                fn walk(dir: &std::path::Path, prefix: &str, out: &mut Vec<(String, PathBuf)>) {
                    for e in store::list(dir).into_iter().filter(|e| e.is_dir) {
                        let label = format!("{prefix}{}/", e.title);
                        out.push((label.clone(), e.path.clone()));
                        walk(&e.path, &label, out);
                    }
                }
                walk(&root, "/", &mut targets);
                egui::ScrollArea::vertical().max_height(260.0).show(ui, |ui| {
                    for (label, path) in &targets {
                        if ui.button(label).clicked() {
                            let ok = items.iter().filter(|e| store::move_entry(e, path)).count();
                            self.toast(l(&format!("{ok} öğe taşındı"), &format!("{ok} item(s) moved")));
                            close = true;
                        }
                    }
                });
                if ui.button(l("İptal", "Cancel")).clicked() { close = true; }
            });
            if close {
                self.moving = None;
                self.selected.clear();
                self.reload();
            }
        }
    }
}

impl eframe::App for App {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        self.handle_msgs(ctx);
        if self.quit {
            self.share.stop();
            ctx.send_viewport_cmd(egui::ViewportCommand::Close);
        }
        // Pencereyi kapatmak uygulamayı kapatmaz; menü çubuğunda çalışmaya devam eder
        if ctx.input(|i| i.viewport().close_requested()) && !self.quit {
            ctx.send_viewport_cmd(egui::ViewportCommand::CancelClose);
            ctx.send_viewport_cmd(egui::ViewportCommand::Visible(false));
        }
        if let Some((_, t)) = &self.toast {
            if t.elapsed() > Duration::from_secs(2) {
                self.toast = None;
            } else {
                ctx.request_repaint_after(Duration::from_millis(300));
            }
        }
        if ctx.input_mut(|i| i.consume_key(Modifiers::COMMAND, Key::F)) {
            if let View::Txt { query, .. } = &mut self.view {
                query.clear();
            }
        }

        egui::TopBottomPanel::top("top").frame(egui::Frame::default().fill(BG).inner_margin(6.0)).show(ctx, |ui| self.ui_top(ui, ctx));
        if matches!(self.view, View::List) {
            egui::TopBottomPanel::bottom("bottom").frame(egui::Frame::default().fill(BG).inner_margin(8.0)).show(ctx, |ui| self.ui_bottom(ui, ctx));
        }
        egui::CentralPanel::default().frame(egui::Frame::default().fill(BG).inner_margin(8.0)).show(ctx, |ui| {
            if matches!(self.view, View::Txt { .. }) {
                self.ui_txt(ui);
            } else {
                self.ui_list(ui, ctx);
            }
            if let Some((t, _)) = &self.toast {
                ui.painter().text(
                    ui.max_rect().center_bottom() - egui::vec2(0.0, 12.0),
                    egui::Align2::CENTER_BOTTOM,
                    t,
                    egui::FontId::proportional(14.0),
                    Color32::WHITE,
                );
            }
        });
        self.ui_share_window(ctx);
        self.ui_dialogs(ctx);
    }
}

fn main() -> eframe::Result<()> {
    let opts = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default().with_inner_size([400.0, 600.0]).with_min_inner_size([300.0, 300.0]).with_title("Notlarım"),
        ..Default::default()
    };
    eframe::run_native("Plan", opts, Box::new(|cc| Ok(Box::new(App::new(cc)))))
}
