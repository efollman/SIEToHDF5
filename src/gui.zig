/// Windows-only GUI for ExportSIE — built with raylib / raygui.
/// Provides file selection, output format, theme detection, and export status.
const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");
const ExportSIE = @import("ExportSIE");

// ── Win32 API for native file dialogs ─────────────────────────────────────
const OPENFILENAMEA = extern struct {
    lStructSize: u32,
    hwndOwner: ?*anyopaque,
    hInstance: ?*anyopaque,
    lpstrFilter: ?[*]const u8,
    lpstrCustomFilter: ?[*]u8,
    nMaxCustFilter: u32,
    nFilterIndex: u32,
    lpstrFile: [*]u8,
    nMaxFile: u32,
    lpstrFileTitle: ?[*]u8,
    nMaxFileTitle: u32,
    lpstrInitialDir: ?[*:0]const u8,
    lpstrTitle: ?[*:0]const u8,
    flags: u32,
    nFileOffset: u16,
    nFileExtension: u16,
    lpstrDefExt: ?[*:0]const u8,
    lCustData: usize,
    lpfnHook: ?*anyopaque,
    lpTemplateName: ?[*:0]const u8,
    pvReserved: ?*anyopaque,
    dwReserved: u32,
    flagsEx: u32,
};

extern "comdlg32" fn GetOpenFileNameA(lpofn: *OPENFILENAMEA) c_int;
extern "ole32" fn CoInitializeEx(pvReserved: ?*anyopaque, dwCoInit: u32) i32;
extern "kernel32" fn SetConsoleOutputCP(wCodePageID: c_uint) c_int;
extern "advapi32" fn RegGetValueA(
    hkey: usize,
    lpSubKey: [*:0]const u8,
    lpValue: [*:0]const u8,
    dwFlags: u32,
    pdwType: ?*u32,
    pvData: ?*anyopaque,
    pcbData: ?*u32,
) i32;

const HKEY_CURRENT_USER: usize = 0x80000001;
const RRF_RT_REG_DWORD: u32 = 0x00000010;

// ── Theme ─────────────────────────────────────────────────────────────────

fn isWindowsDarkMode() bool {
    var data: u32 = 1;
    var size: u32 = @sizeOf(u32);
    const result = RegGetValueA(
        HKEY_CURRENT_USER,
        "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
        "AppsUseLightTheme",
        RRF_RT_REG_DWORD,
        null,
        @ptrCast(&data),
        &size,
    );
    return result == 0 and data == 0;
}

const Theme = struct {
    bg: rl.Color,
    accent_line: rl.Color,
    label: rl.Color,
    hint: rl.Color,
    status_running: rl.Color,
    status_done: rl.Color,
    status_err: rl.Color,
    rg_bg: i32,
    rg_btn_normal: i32,
    rg_btn_text: i32,
    rg_btn_border: i32,
    rg_btn_focused: i32,
    rg_btn_focused_text: i32,
    rg_btn_focused_border: i32,
    rg_btn_pressed: i32,
    rg_btn_pressed_text: i32,
    rg_btn_pressed_border: i32,
    rg_btn_disabled: i32,
    rg_btn_disabled_text: i32,
    rg_btn_disabled_border: i32,
    rg_tb_bg: i32,
    rg_tb_border: i32,
    rg_tb_text: i32,
    rg_tb_focused_bg: i32,
    rg_tb_focused_border: i32,
    rg_tb_focused_text: i32,
    rg_label_text: i32,
};

fn rgba(r: u8, g: u8, b: u8, a: u8) i32 {
    return @bitCast((@as(u32, r) << 24) | (@as(u32, g) << 16) | (@as(u32, b) << 8) | @as(u32, a));
}

fn lightTheme() Theme {
    return .{
        .bg = rl.Color.init(241, 245, 249, 255),
        .accent_line = rl.Color.init(15, 23, 42, 255),
        .label = rl.Color.init(71, 85, 105, 255),
        .hint = rl.Color.init(148, 163, 184, 255),
        .status_running = rl.Color.init(37, 99, 235, 255),
        .status_done = rl.Color.init(22, 163, 74, 255),
        .status_err = rl.Color.init(220, 38, 38, 255),
        .rg_bg = rgba(241, 245, 249, 255),
        .rg_btn_normal = rgba(37, 99, 235, 255),
        .rg_btn_text = rgba(255, 255, 255, 255),
        .rg_btn_border = rgba(30, 78, 216, 255),
        .rg_btn_focused = rgba(59, 130, 246, 255),
        .rg_btn_focused_text = rgba(255, 255, 255, 255),
        .rg_btn_focused_border = rgba(37, 99, 235, 255),
        .rg_btn_pressed = rgba(29, 78, 216, 255),
        .rg_btn_pressed_text = rgba(255, 255, 255, 255),
        .rg_btn_pressed_border = rgba(30, 64, 175, 255),
        .rg_btn_disabled = rgba(148, 163, 184, 255),
        .rg_btn_disabled_text = rgba(226, 232, 240, 255),
        .rg_btn_disabled_border = rgba(148, 163, 184, 255),
        .rg_tb_bg = rgba(255, 255, 255, 255),
        .rg_tb_border = rgba(203, 213, 225, 255),
        .rg_tb_text = rgba(30, 41, 59, 255),
        .rg_tb_focused_bg = rgba(255, 255, 255, 255),
        .rg_tb_focused_border = rgba(59, 130, 246, 255),
        .rg_tb_focused_text = rgba(30, 41, 59, 255),
        .rg_label_text = rgba(71, 85, 105, 255),
    };
}

fn darkTheme() Theme {
    return .{
        .bg = rl.Color.init(24, 24, 27, 255),
        .accent_line = rl.Color.init(59, 130, 246, 255),
        .label = rl.Color.init(161, 161, 170, 255),
        .hint = rl.Color.init(113, 113, 122, 255),
        .status_running = rl.Color.init(96, 165, 250, 255),
        .status_done = rl.Color.init(74, 222, 128, 255),
        .status_err = rl.Color.init(248, 113, 113, 255),
        .rg_bg = rgba(24, 24, 27, 255),
        .rg_btn_normal = rgba(37, 99, 235, 255),
        .rg_btn_text = rgba(255, 255, 255, 255),
        .rg_btn_border = rgba(29, 78, 216, 255),
        .rg_btn_focused = rgba(59, 130, 246, 255),
        .rg_btn_focused_text = rgba(255, 255, 255, 255),
        .rg_btn_focused_border = rgba(59, 130, 246, 255),
        .rg_btn_pressed = rgba(29, 78, 216, 255),
        .rg_btn_pressed_text = rgba(255, 255, 255, 255),
        .rg_btn_pressed_border = rgba(30, 64, 175, 255),
        .rg_btn_disabled = rgba(63, 63, 70, 255),
        .rg_btn_disabled_text = rgba(113, 113, 122, 255),
        .rg_btn_disabled_border = rgba(63, 63, 70, 255),
        .rg_tb_bg = rgba(39, 39, 42, 255),
        .rg_tb_border = rgba(63, 63, 70, 255),
        .rg_tb_text = rgba(212, 212, 216, 255),
        .rg_tb_focused_bg = rgba(39, 39, 42, 255),
        .rg_tb_focused_border = rgba(59, 130, 246, 255),
        .rg_tb_focused_text = rgba(212, 212, 216, 255),
        .rg_label_text = rgba(161, 161, 170, 255),
    };
}

// ── Constants ─────────────────────────────────────────────────────────────

const WINDOW_W = 640;
const WINDOW_H_MIN = 340;
const PAD: f32 = 16;
const FIELD_H: f32 = 32;
const FILE_ROW_H: f32 = 36; // height of each queued-file row
const MAX_VISIBLE_FILES_SOFT: usize = 10; // soft cap for *initial* auto-sized window; user can resize window to show more or fewer

// Vertical pixels consumed by everything except the file-list rows.
// Used to derive the dynamic visible-row count from the current window height.
//   PAD (top)
// + 22 ("Files to Export" label/Add button row)
// + 12 (gap below list)
// + 22 ("Output Folder" label) + FIELD_H + 16 (output box row + spacing)
// + (FIELD_H + 8) + 16 (Export All button + spacing)
// + 22 ("Formats" label) + 18 (checkbox row, cb_size) + 16 (spacing)
// + 8  (bottom margin)
const NON_LIST_FIXED_H: f32 = PAD + 22 + 12 + 22 + FIELD_H + 16 + (FIELD_H + 8) + 16 + 22 + 18 + 8 + 18 + 16 + 8;

// Output extensions in the same order as FORMAT_SHORT.
const FORMAT_EXTS = [_][]const u8{ ".h5", ".txt", ".csv", ".xlsx", ".asc" };

// ── Application state ─────────────────────────────────────────────────────

const FileState = enum { idle, running, done, err };

/// Per-file export result written by the worker thread.
const FileResult = struct {
    success: bool = true,
    message: [256]u8 = [_]u8{0} ** 256,
    message_len: usize = 0,
};

const NUM_FORMATS: usize = 5;
/// Short labels shown in per-format status badges.
const FORMAT_SHORT = [_][:0]const u8{ "H5", "TXT", "CSV", "XLSX", "ASC" };
/// Long labels shown next to format checkboxes.
const FORMAT_LABEL = [_][:0]const u8{ "H5", "TXT", "CSV", "XLSX", "Vector Style ASCII (CAN only)" };

/// Per-format task associated with a single input file.
const FormatTask = struct {
    state: FileState = .idle,
    result: FileResult = .{},
    done: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    thread: ?std.Thread = null,
    anim_frame: u32 = 0,
};

/// One entry in the file queue. Each file may produce up to NUM_FORMATS outputs.
const FileItem = struct {
    /// Full input path (heap-allocated, owned by this item).
    in_path: [:0]u8,
    tasks: [NUM_FORMATS]FormatTask,

    fn deinit(self: *FileItem, allocator: std.mem.Allocator) void {
        for (&self.tasks) |*t| {
            if (t.thread) |th| th.detach();
        }
        allocator.free(self.in_path);
    }

    fn anyRunning(self: *const FileItem) bool {
        for (&self.tasks) |*t| if (t.state == .running) return true;
        return false;
    }
};

const AppState = struct {
    /// Output folder (no filename – name is derived from each input stem at export time).
    out_dir_buf: [512:0]u8 = [_:0]u8{0} ** 512,
    out_dir_edit: bool = false,
    font: rl.Font = undefined,
    font_loaded: bool = false,
    /// Which formats are selected for export
    /// (0=HDF5, 1=ASCII, 2=CSV, 3=XLSX, 4=Vector ASC).
    /// Default to none selected; the on-disk config restores the user's last
    /// selection at startup (see loadConfig / saveConfig).
    format_selected: [NUM_FORMATS]bool = .{ false, false, false, false, false },
    /// Queue of files to export
    files: std.ArrayListUnmanaged(FileItem) = .{},
    /// Scroll offset (pixels) for the file queue list.
    scroll_offset: f32 = 0,
    /// True once the user has manually resized the window. While true, the GUI
    /// stops auto-fitting window height to content and instead lets the visible
    /// row count expand/shrink with the user's chosen window size.
    user_resized: bool = false,
    /// Window height that we last set programmatically; used to detect manual
    /// resizes (any height delta we didn't cause).
    last_set_h: i32 = 0,
    /// File count from the previous frame; a change resets `user_resized` so
    /// the window snaps back to the soft-cap-based size on add/remove.
    prev_file_count: usize = 0,
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) AppState {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *AppState) void {
        for (self.files.items) |*f| f.deinit(self.allocator);
        self.files.deinit(self.allocator);
    }

    fn outDirLen(self: *const AppState) usize {
        return std.mem.indexOfScalar(u8, &self.out_dir_buf, 0) orelse self.out_dir_buf.len;
    }

    fn setOutDir(self: *AppState, path: []const u8) void {
        const len = @min(path.len, self.out_dir_buf.len - 1);
        @memcpy(self.out_dir_buf[0..len], path[0..len]);
        self.out_dir_buf[len] = 0;
    }

    /// Add a file to the queue if not already present. Returns whether it was added.
    fn addFile(self: *AppState, in_path: []const u8) bool {
        for (self.files.items) |*f| {
            if (std.mem.eql(u8, f.in_path, in_path)) return false;
        }
        const duped = self.allocator.dupeZ(u8, in_path) catch return false;
        var item = FileItem{
            .in_path = duped,
            .tasks = undefined,
        };
        for (&item.tasks) |*t| t.* = .{};
        self.files.append(self.allocator, item) catch {
            self.allocator.free(duped);
            return false;
        };
        return true;
    }

    fn removeFile(self: *AppState, idx: usize) void {
        if (idx >= self.files.items.len) return;
        self.files.items[idx].deinit(self.allocator);
        _ = self.files.orderedRemove(idx);
    }

    /// True if any file's any task is currently exporting.
    fn anyRunning(self: *const AppState) bool {
        for (self.files.items) |*f| if (f.anyRunning()) return true;
        return false;
    }

    /// True if at least one selected-format task across all files has reached
    /// the .done state and none are still .idle, .running, or .err. Used to
    /// decide when to show the "all complete" check next to Export All.
    fn allSelectedDone(self: *const AppState) bool {
        if (self.files.items.len == 0) return false;
        var any_done = false;
        var any_selected = false;
        for (self.files.items) |*f| {
            for (0..NUM_FORMATS) |fmt_i| {
                if (!self.format_selected[fmt_i]) continue;
                any_selected = true;
                switch (f.tasks[fmt_i].state) {
                    .done => any_done = true,
                    .idle, .running, .err => return false,
                }
            }
        }
        return any_selected and any_done;
    }

    /// True if at least one format checkbox is selected.
    fn anyFormatSelected(self: *const AppState) bool {
        for (self.format_selected) |s| if (s) return true;
        return false;
    }
};

// ── Entry point ───────────────────────────────────────────────────────────

pub fn main() !void {
    _ = SetConsoleOutputCP(65001);
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Request 4x MSAA before window creation so line / circle / triangle
    // primitives (spinner, check mark, scrollbar) have smoother edges.
    rl.setConfigFlags(.{ .msaa_4x_hint = true, .window_resizable = true });
    rl.initWindow(WINDOW_W, WINDOW_H_MIN, "ExportSIE");
    defer rl.closeWindow();
    rl.setWindowMinSize(WINDOW_W, WINDOW_H_MIN);
    rl.setWindowState(.{ .window_resizable = true });
    rl.setTargetFPS(60);

    // Load system font
    const font_paths = [_][:0]const u8{
        "C:/Windows/Fonts/segoeui.ttf",
        "C:/Windows/Fonts/tahoma.ttf",
        "C:/Windows/Fonts/arial.ttf",
    };
    var app_font: ?rl.Font = null;
    for (font_paths) |fpath| {
        if (rl.loadFontEx(fpath, 32, null)) |f| {
            app_font = f;
            break;
        } else |_| {}
    }
    if (app_font) |f| {
        rg.setFont(f);
        rl.setTextureFilter(f.texture, .bilinear);
    }
    defer if (app_font) |f| f.unload();

    rg.setStyle(.default, .{ .default = .text_size }, 18);

    var dark_mode = isWindowsDarkMode();
    var theme = if (dark_mode) darkTheme() else lightTheme();
    applyTheme(&theme);
    // Poll the OS theme periodically (not every frame — registry read is cheap
    // but we don't need 60 Hz)
    var theme_check_counter: u32 = 0;

    var app = AppState.init(allocator);
    defer app.deinit();
    loadConfig(&app);
    defer saveConfig(&app);
    if (app_font) |f| {
        app.font = f;
        app.font_loaded = true;
    }

    while (!rl.windowShouldClose()) {
        // ── Live theme switch — poll OS dark/light setting ────────────
        theme_check_counter +%= 1;
        if (theme_check_counter % 30 == 0) {
            const new_dark = isWindowsDarkMode();
            if (new_dark != dark_mode) {
                dark_mode = new_dark;
                theme = if (dark_mode) darkTheme() else lightTheme();
                applyTheme(&theme);
            }
        }

        // ── Poll per-file thread completion ──────────────────────────
        for (app.files.items) |*f| {
            for (&f.tasks) |*t| {
                if (t.state == .running and t.done.load(.acquire)) {
                    t.done.store(false, .monotonic);
                    if (t.thread) |th| {
                        th.detach();
                        t.thread = null;
                    }
                    t.state = if (t.result.success) .done else .err;
                }
            }
        }

        // ── Handle file drop ──────────────────────────────────────────
        if (rl.isFileDropped()) {
            const dropped = rl.loadDroppedFiles();
            defer rl.unloadDroppedFiles(dropped);
            for (0..dropped.count) |i| {
                const path = std.mem.span(dropped.paths[i]);
                _ = app.addFile(path);
            }
            // Set output dir from the first new file's directory if not yet set
            if (app.outDirLen() == 0 and dropped.count > 0) {
                const p = std.mem.span(dropped.paths[0]);
                if (dirOf(p)) |d| app.setOutDir(d);
            }
        }

        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(theme.bg);

        const win_w: i32 = rl.getScreenWidth();
        const win_wf: f32 = @floatFromInt(win_w);
        const padi: i32 = @intFromFloat(PAD);

        // Accent line
        rl.drawRectangle(0, 0, win_w, 3, theme.accent_line);

        var y: f32 = PAD;

        // ── File Queue label + Add Files button ───────────────────────
        drawFont(app.font_loaded, app.font, "Files to Export", padi, @intFromFloat(y), 15, theme.label);
        if (rg.button(rl.Rectangle.init(win_wf - PAD - 130, y - 2, 130, 26), "Add Files...")) {
            const paths = openMultiFileDialog(allocator) catch null;
            if (paths) |ps| {
                defer {
                    for (ps) |p| allocator.free(p);
                    allocator.free(ps);
                }
                for (ps) |p| {
                    _ = app.addFile(p);
                }
                if (app.outDirLen() == 0 and ps.len > 0) {
                    if (dirOf(ps[0])) |d| app.setOutDir(d);
                }
            }
        }
        y += 22;

        // ── File rows ────────────────────────────────────────────────
        var remove_idx: ?usize = null;
        // Compute right-side area used by per-format badges
        var num_selected: usize = 0;
        for (app.format_selected) |s| {
            if (s) num_selected += 1;
        }
        const badge_w: f32 = 56;
        const remove_w: f32 = 22;
        const status_area_w: f32 = if (num_selected > 0)
            @as(f32, @floatFromInt(num_selected)) * badge_w + remove_w + 12
        else
            remove_w + 12;

        // Scrollable list geometry. The visible row count is derived from the
        // current window height; MAX_VISIBLE_FILES_SOFT only governs the
        // *initial* programmatically-sized window when files are first added.
        const total_rows = app.files.items.len;
        const cur_h_now = rl.getScreenHeight();
        const cur_hf: f32 = @floatFromInt(cur_h_now);
        const avail_for_list: f32 = @max(FILE_ROW_H, cur_hf - NON_LIST_FIXED_H);
        const dynamic_max: usize = @max(@as(usize, 1), @as(usize, @intFromFloat(@floor(avail_for_list / FILE_ROW_H))));
        const visible_rows = @min(total_rows, dynamic_max);
        const list_y = y;
        const list_h: f32 = @as(f32, @floatFromInt(visible_rows)) * FILE_ROW_H;
        const overflow = total_rows > visible_rows;
        const max_scroll: f32 = if (overflow)
            @as(f32, @floatFromInt(total_rows - visible_rows)) * FILE_ROW_H
        else
            0;

        if (overflow) {
            const list_rect = rl.Rectangle.init(PAD, list_y, win_wf - PAD * 2, list_h);
            if (rl.checkCollisionPointRec(rl.getMousePosition(), list_rect)) {
                const wheel = rl.getMouseWheelMove();
                if (wheel != 0) {
                    app.scroll_offset -= wheel * FILE_ROW_H;
                    if (app.scroll_offset < 0) app.scroll_offset = 0;
                    if (app.scroll_offset > max_scroll) app.scroll_offset = max_scroll;
                }
            }
        } else {
            app.scroll_offset = 0;
        }

        // Only render rows whose row rect intersects the visible band so that
        // raygui buttons drawn outside the band can't be clicked.
        const first_visible: usize = @intFromFloat(@floor(app.scroll_offset / FILE_ROW_H));
        const last_visible: usize = @min(total_rows, first_visible + visible_rows + 1);

        rl.beginScissorMode(padi, @intFromFloat(list_y), @intFromFloat(win_wf - PAD * 2), @intFromFloat(list_h));
        var fi: usize = first_visible;
        while (fi < last_visible) : (fi += 1) {
            const f = &app.files.items[fi];
            const fy = list_y + @as(f32, @floatFromInt(fi)) * FILE_ROW_H - app.scroll_offset;
            const row_w = win_wf - PAD * 2;

            // Background stripe
            const stripe_color = if (fi % 2 == 0)
                rl.Color.init(0, 0, 0, if (dark_mode) 20 else 10)
            else
                rl.Color.init(0, 0, 0, 0);
            rl.drawRectangle(padi, @intFromFloat(fy), @intFromFloat(row_w), @intFromFloat(FILE_ROW_H), stripe_color);

            // Truncated path — fit within row width minus badge/remove area
            var trunc_buf: [256:0]u8 = [_:0]u8{0} ** 256;
            const path_max_px: f32 = row_w - status_area_w - 8;
            truncateMidToWidth(f.in_path, &trunc_buf, path_max_px, app.font_loaded, app.font, 15);
            drawFont(app.font_loaded, app.font, &trunc_buf, padi + 4, @intFromFloat(fy + 10), 15, theme.label);

            // Per-format badges (only for selected formats), laid out right→left
            var badge_x: f32 = win_wf - PAD - remove_w - 6 - badge_w;
            for (0..NUM_FORMATS) |fmt_i| {
                if (!app.format_selected[fmt_i]) continue;
                const t = &f.tasks[fmt_i];
                const label = FORMAT_SHORT[fmt_i];

                const status_color = switch (t.state) {
                    .idle => theme.hint,
                    .running => theme.status_running,
                    .done => theme.status_done,
                    .err => theme.status_err,
                };
                drawFont(app.font_loaded, app.font, label, @intFromFloat(badge_x), @intFromFloat(fy + 11), 13, status_color);

                // Status indicator at the right of the badge
                const ind_cx = badge_x + badge_w - 14;
                const ind_cy = fy + FILE_ROW_H / 2;
                switch (t.state) {
                    .idle => {},
                    .running => {
                        t.anim_frame +%= 1;
                        const num_spokes: usize = 8;
                        for (0..num_spokes) |si| {
                            const sif: f32 = @floatFromInt(si);
                            const angle = (sif * 2.0 * std.math.pi / @as(f32, @floatFromInt(num_spokes))) +
                                (@as(f32, @floatFromInt(t.anim_frame)) * 0.12);
                            const ax = ind_cx + 5.0 * @cos(angle);
                            const ay = ind_cy + 5.0 * @sin(angle);
                            const phase: u8 = @intCast((si + t.anim_frame / 3) % num_spokes);
                            const bright: u8 = @intCast(40 + @as(usize, phase) * 215 / (num_spokes - 1));
                            rl.drawCircle(@intFromFloat(ax), @intFromFloat(ay), 1.8, rl.Color.init(96, 165, 250, bright));
                        }
                    },
                    .done => drawCheck(ind_cx, ind_cy, 1.0, theme.status_done),
                    .err => {
                        rl.drawLineEx(
                            .{ .x = ind_cx - 5, .y = ind_cy - 5 },
                            .{ .x = ind_cx + 5, .y = ind_cy + 5 },
                            2,
                            theme.status_err,
                        );
                        rl.drawLineEx(
                            .{ .x = ind_cx - 5, .y = ind_cy + 5 },
                            .{ .x = ind_cx + 5, .y = ind_cy - 5 },
                            2,
                            theme.status_err,
                        );
                    },
                }
                badge_x -= badge_w;
            }

            // Remove button (only when no task is running)
            if (!f.anyRunning()) {
                if (rg.button(rl.Rectangle.init(win_wf - PAD - remove_w, fy + (FILE_ROW_H - 20) / 2, remove_w, 20), "x")) {
                    remove_idx = fi;
                }
            }
        }
        rl.endScissorMode();

        // Scrollbar indicator (visual only; wheel handles scrolling)
        if (overflow) {
            const sb_w: f32 = 4;
            const sb_x = win_wf - PAD - sb_w + 1;
            const track_color = rl.Color.init(0, 0, 0, if (dark_mode) 40 else 25);
            rl.drawRectangle(@intFromFloat(sb_x), @intFromFloat(list_y), @intFromFloat(sb_w), @intFromFloat(list_h), track_color);
            const ratio = @as(f32, @floatFromInt(visible_rows)) / @as(f32, @floatFromInt(total_rows));
            const thumb_h = @max(20, list_h * ratio);
            const thumb_y = list_y + (list_h - thumb_h) * (app.scroll_offset / max_scroll);
            const thumb_color = rl.Color.init(if (dark_mode) 180 else 100, if (dark_mode) 180 else 100, if (dark_mode) 180 else 100, 200);
            rl.drawRectangle(@intFromFloat(sb_x), @intFromFloat(thumb_y), @intFromFloat(sb_w), @intFromFloat(thumb_h), thumb_color);
        }

        y = list_y + list_h;
        if (remove_idx) |ri| {
            app.removeFile(ri);
            // Clamp scroll after removal
            const new_total = app.files.items.len;
            const new_max: f32 = if (new_total > visible_rows)
                @as(f32, @floatFromInt(new_total - visible_rows)) * FILE_ROW_H
            else
                0;
            if (app.scroll_offset > new_max) app.scroll_offset = new_max;
        }

        if (app.files.items.len == 0) {
            const hint = "Add .sie files above or drag them onto this window.";
            const hint_tw = measureFont(app.font_loaded, app.font, hint, 14);
            drawFont(app.font_loaded, app.font, hint, @divTrunc(win_w - hint_tw, 2), @intFromFloat(y + 8), 14, theme.hint);
            y += FILE_ROW_H;
        }

        y += 12;

        // ── Output Folder ──────────────────────────────────────────────
        drawFont(app.font_loaded, app.font, "Output Folder", padi, @intFromFloat(y), 15, theme.label);
        y += 22;
        const out_box_w = win_wf - PAD * 2 - 100;
        if (app.out_dir_edit) {
            // Editable: show real textbox with full string
            if (rg.textBox(rl.Rectangle.init(PAD, y, out_box_w, FIELD_H), &app.out_dir_buf, @intCast(app.out_dir_buf.len), app.out_dir_edit)) {
                app.out_dir_edit = !app.out_dir_edit;
            }
        } else {
            // Read-only: draw textbox background then overlay truncated path text manually
            // (avoids the disabled-style colors that made it look like white-on-grey in dark mode)
            const tb_rect = rl.Rectangle.init(PAD, y, out_box_w, FIELD_H);
            rl.drawRectangleRec(tb_rect, themeColor32(theme.rg_tb_bg));
            rl.drawRectangleLinesEx(tb_rect, 1, themeColor32(theme.rg_tb_border));
            if (app.outDirLen() > 0) {
                var trunc_buf: [256:0]u8 = [_:0]u8{0} ** 256;
                truncateMidToWidth(app.out_dir_buf[0..app.outDirLen()], &trunc_buf, out_box_w - 12, app.font_loaded, app.font, 15);
                drawFont(app.font_loaded, app.font, &trunc_buf, padi + 6, @intFromFloat(y + (FIELD_H - 18) / 2), 15, themeColor32(theme.rg_tb_text));
            }
            if (rl.checkCollisionPointRec(rl.getMousePosition(), tb_rect) and rl.isMouseButtonPressed(.left)) {
                app.out_dir_edit = true;
            }
        }
        if (rg.button(rl.Rectangle.init(win_wf - PAD - 90, y, 90, FIELD_H), "Browse...")) {
            if (browseFolder(allocator)) |path| {
                defer allocator.free(path);
                app.setOutDir(path);
            }
        }
        y += FIELD_H + 16;

        // ── Export All button ─────────────────────────────────────────
        const can_export = app.files.items.len > 0 and app.outDirLen() > 0 and
            !app.anyRunning() and app.anyFormatSelected();
        if (!can_export) rg.disable();
        if (rg.button(rl.Rectangle.init(PAD, y, 160, FIELD_H + 8), "Export All")) {
            for (app.files.items) |*f| {
                for (0..NUM_FORMATS) |fmt_i| {
                    if (!app.format_selected[fmt_i]) continue;
                    const t = &f.tasks[fmt_i];
                    if (t.state != .running) {
                        startFormatExport(&app, f, fmt_i);
                    }
                }
            }
        }
        if (!can_export) rg.enable();

        // Overall progress indicator next to the Export All button.
        // Spinner while any task is running; check mark only when at least one
        // task has finished AND nothing is still running AND no tasks errored.
        const ind_cx: f32 = PAD + 160 + 20;
        const ind_cy: f32 = y + (FIELD_H + 8) / 2;
        if (app.anyRunning()) {
            const frame: u32 = @intFromFloat(rl.getTime() * 30.0);
            const num_spokes: usize = 8;
            for (0..num_spokes) |si| {
                const sif: f32 = @floatFromInt(si);
                const angle = sif * 2.0 * std.math.pi / @as(f32, @floatFromInt(num_spokes)) +
                    @as(f32, @floatFromInt(frame)) * 0.12;
                const ax = ind_cx + 7.0 * @cos(angle);
                const ay = ind_cy + 7.0 * @sin(angle);
                const phase: u8 = @intCast((si + frame / 3) % num_spokes);
                const bright: u8 = @intCast(40 + @as(usize, phase) * 215 / (num_spokes - 1));
                rl.drawCircle(@intFromFloat(ax), @intFromFloat(ay), 2.2, rl.Color.init(96, 165, 250, bright));
            }
        } else if (app.allSelectedDone()) {
            drawCheck(ind_cx, ind_cy, 1.5, theme.status_done);
        }
        y += FIELD_H + 16;

        // ── Format checkboxes (below export button) ───────────────────
        drawFont(app.font_loaded, app.font, "Formats", padi, @intFromFloat(y), 15, theme.label);
        y += 22;
        const cb_size: f32 = 18;
        const cb_spacing: f32 = 90;
        // First 4 short-labelled formats on one row.
        for (0..4) |fmt_i| {
            const cx = PAD + @as(f32, @floatFromInt(fmt_i)) * cb_spacing;
            _ = rg.checkBox(rl.Rectangle.init(cx, y, cb_size, cb_size), FORMAT_LABEL[fmt_i], &app.format_selected[fmt_i]);
        }
        y += cb_size + 8;
        // Vector ASC gets its own row because the label is long.
        _ = rg.checkBox(rl.Rectangle.init(PAD, y, cb_size, cb_size), FORMAT_LABEL[4], &app.format_selected[4]);
        y += cb_size + 16;

        // ── Window auto-fit ───────────────────────────────────────────
        // Detect manual resize: any height delta we didn't program.
        const cur_h = rl.getScreenHeight();
        if (app.last_set_h != 0 and cur_h != app.last_set_h) {
            app.user_resized = true;
        }
        // Reset on file count change so the window snaps back to fit the new
        // soft-capped target when the user adds/removes files.
        if (app.files.items.len != app.prev_file_count) {
            app.user_resized = false;
            app.prev_file_count = app.files.items.len;
        }
        if (!app.user_resized) {
            const target_visible = @min(total_rows, MAX_VISIBLE_FILES_SOFT);
            const target_list_h: f32 = @as(f32, @floatFromInt(target_visible)) * FILE_ROW_H;
            const target_h_f: f32 = NON_LIST_FIXED_H + target_list_h;
            const target_h: i32 = @max(WINDOW_H_MIN, @as(i32, @intFromFloat(target_h_f)));
            if (target_h != cur_h) {
                rl.setWindowSize(win_w, target_h);
                app.last_set_h = target_h;
            } else {
                app.last_set_h = cur_h;
            }
        } else {
            app.last_set_h = cur_h;
        }
    }
}

// ── Export dispatch ───────────────────────────────────────────────────────

const FormatExportJob = struct {
    task: *FormatTask,
    format_idx: usize,
    allocator: std.mem.Allocator,
    in_path: []const u8,
    out_path: []const u8,
};

fn formatExportWorker(job: *FormatExportJob) void {
    defer job.allocator.destroy(job);
    defer job.allocator.free(job.in_path);
    defer job.allocator.free(job.out_path);

    var result = FileResult{};

    // Null-terminate paths for the convert() functions
    const in_z = job.allocator.dupeZ(u8, job.in_path) catch {
        result.success = false;
        result.message_len = (std.fmt.bufPrint(&result.message, "Out of memory", .{}) catch "").len;
        job.task.result = result;
        job.task.done.store(true, .release);
        return;
    };
    defer job.allocator.free(in_z);
    const out_z = job.allocator.dupeZ(u8, job.out_path) catch {
        result.success = false;
        result.message_len = (std.fmt.bufPrint(&result.message, "Out of memory", .{}) catch "").len;
        job.task.result = result;
        job.task.done.store(true, .release);
        return;
    };
    defer job.allocator.free(out_z);

    switch (job.format_idx) {
        0 => ExportSIE.hdf5_export.convert(job.allocator, in_z, out_z) catch |err| {
            result.success = false;
            result.message_len = (std.fmt.bufPrint(&result.message, "HDF5: {}", .{err}) catch "").len;
        },
        1 => ExportSIE.ascii_export.convert(job.allocator, in_z, out_z) catch |err| {
            result.success = false;
            result.message_len = (std.fmt.bufPrint(&result.message, "ASCII: {}", .{err}) catch "").len;
        },
        2 => ExportSIE.csv_export.convert(job.allocator, in_z, out_z) catch |err| {
            result.success = false;
            result.message_len = (std.fmt.bufPrint(&result.message, "CSV: {}", .{err}) catch "").len;
        },
        3 => ExportSIE.xlsx_export.convert(job.allocator, in_z, out_z) catch |err| {
            result.success = false;
            result.message_len = (std.fmt.bufPrint(&result.message, "XLSX: {}", .{err}) catch "").len;
        },
        4 => ExportSIE.vector_asc_export.convert(job.allocator, in_z, out_z) catch |err| {
            result.success = false;
            result.message_len = (std.fmt.bufPrint(&result.message, "ASC: {}", .{err}) catch "").len;
        },
        else => {
            result.success = false;
            result.message_len = (std.fmt.bufPrint(&result.message, "Bad format idx", .{}) catch "").len;
        },
    }

    job.task.result = result;
    job.task.done.store(true, .release);
}

/// Build an output path: out_dir/stem.ext, where ext is selected by format_idx.
/// Vector ASC outputs are prefixed with "Vector-" so they don't collide with
/// the basic ASCII export when both formats are selected.
fn buildOutPath(allocator: std.mem.Allocator, in_path: []const u8, out_dir: []const u8, format_idx: usize) ?[]u8 {
    const sep_idx = std.mem.lastIndexOfAny(u8, in_path, "/\\") orelse 0;
    const filename = if (sep_idx > 0) in_path[sep_idx + 1 ..] else in_path;
    const dot_idx = std.mem.lastIndexOfScalar(u8, filename, '.') orelse filename.len;
    const stem = filename[0..dot_idx];
    const ext = FORMAT_EXTS[format_idx];
    const dir = std.mem.trimRight(u8, out_dir, "/\\");
    const prefix: []const u8 = if (format_idx == 4) "Vector-" else "";
    return std.fmt.allocPrint(allocator, "{s}\\{s}{s}{s}", .{ dir, prefix, stem, ext }) catch null;
}

fn startFormatExport(app: *AppState, f: *FileItem, format_idx: usize) void {
    if (format_idx >= NUM_FORMATS) return;
    const out_dir = app.out_dir_buf[0..app.outDirLen()];
    if (out_dir.len == 0) return;

    const t = &f.tasks[format_idx];
    const out_path = buildOutPath(app.allocator, f.in_path, out_dir, format_idx) orelse return;

    t.state = .running;
    t.anim_frame = 0;
    t.result = .{};
    t.done.store(false, .monotonic);

    const job = app.allocator.create(FormatExportJob) catch {
        app.allocator.free(out_path);
        t.state = .err;
        t.result.success = false;
        t.result.message_len = (std.fmt.bufPrint(&t.result.message, "Out of memory", .{}) catch "").len;
        return;
    };
    job.* = .{
        .task = t,
        .format_idx = format_idx,
        .allocator = app.allocator,
        .in_path = app.allocator.dupe(u8, f.in_path) catch {
            app.allocator.free(out_path);
            app.allocator.destroy(job);
            t.state = .err;
            return;
        },
        .out_path = out_path,
    };

    t.thread = std.Thread.spawn(.{}, formatExportWorker, .{job}) catch |err| {
        app.allocator.free(job.out_path);
        app.allocator.free(job.in_path);
        app.allocator.destroy(job);
        t.state = .err;
        t.result.success = false;
        t.result.message_len = (std.fmt.bufPrint(&t.result.message, "Thread: {}", .{err}) catch "").len;
        return;
    };
}

/// Return the directory portion of a path (up to and including the last separator).
fn dirOf(path: []const u8) ?[]const u8 {
    if (std.mem.lastIndexOfAny(u8, path, "/\\")) |idx| return path[0..idx];
    return null;
}

/// Truncate a path to at most `max_chars` characters, replacing middle with "...".
/// Output is written into `out` as a null-terminated string.
fn truncateMid(path: []const u8, out: []u8, max_chars: usize) void {
    if (path.len <= max_chars) {
        const l = @min(path.len, out.len - 1);
        @memcpy(out[0..l], path[0..l]);
        out[l] = 0;
        return;
    }
    // Keep first keep_left chars + "..." + last keep_right chars
    const ellipsis = "...";
    const available = if (max_chars > ellipsis.len) max_chars - ellipsis.len else 0;
    const keep_left = available / 2;
    const keep_right = available - keep_left;
    var pos: usize = 0;
    const left_l = @min(keep_left, path.len);
    const right_start = if (path.len >= keep_right) path.len - keep_right else 0;
    if (pos + left_l + ellipsis.len + keep_right < out.len) {
        @memcpy(out[pos .. pos + left_l], path[0..left_l]);
        pos += left_l;
        @memcpy(out[pos .. pos + ellipsis.len], ellipsis);
        pos += ellipsis.len;
        @memcpy(out[pos .. pos + keep_right], path[right_start..]);
        pos += keep_right;
    } else {
        const l = @min(path.len, out.len - 1);
        @memcpy(out[0..l], path[0..l]);
        pos = l;
    }
    out[pos] = 0;
}

/// Truncate a path so its rendered width fits within `max_px` pixels.
/// Uses the actual font metrics, so the truncation adapts to window resizing.
fn truncateMidToWidth(
    path: []const u8,
    out: [:0]u8,
    max_px: f32,
    font_loaded: bool,
    font: rl.Font,
    font_size: f32,
) void {
    // Quick path: full string fits
    {
        const copy_len = @min(path.len, out.len);
        @memcpy(out[0..copy_len], path[0..copy_len]);
        if (copy_len < out.len) out[copy_len] = 0 else out[out.len - 1] = 0;
        const w: f32 = @floatFromInt(measureFont(font_loaded, font, out[0..copy_len :0], font_size));
        if (w <= max_px and copy_len == path.len) return;
    }

    // Binary search the largest total char count whose middle-truncated form fits
    var lo: usize = 3; // at minimum show "..."
    var hi: usize = path.len;
    var best: usize = 0;
    while (lo <= hi) {
        const mid = (lo + hi) / 2;
        truncateMid(path, out, mid);
        const used = std.mem.indexOfScalar(u8, out, 0) orelse out.len;
        const w: f32 = @floatFromInt(measureFont(font_loaded, font, out[0..used :0], font_size));
        if (w <= max_px) {
            best = mid;
            lo = mid + 1;
        } else {
            if (mid == 0) break;
            hi = mid - 1;
        }
    }
    truncateMid(path, out, if (best == 0) 3 else best);
}

/// Convert a packed RGBA i32 (as stored in Theme) back into an rl.Color.
fn themeColor32(packed_rgba: i32) rl.Color {
    const u: u32 = @bitCast(packed_rgba);
    return rl.Color.init(
        @truncate(u >> 24),
        @truncate(u >> 16),
        @truncate(u >> 8),
        @truncate(u),
    );
}

// ── File dialogs ──────────────────────────────────────────────────────────

/// Open multi-select file dialog. Returns a slice of owned paths (caller frees each + the slice).
fn openMultiFileDialog(allocator: std.mem.Allocator) ![][]const u8 {
    _ = CoInitializeEx(null, 0x2);
    // Large buffer: multi-select returns "dir\0file1\0file2\0...\0\0"
    const BUF_LEN = 32768;
    const file_buf = try allocator.alloc(u8, BUF_LEN);
    defer allocator.free(file_buf);
    @memset(file_buf, 0);

    var ofn = OPENFILENAMEA{
        .lStructSize = @sizeOf(OPENFILENAMEA),
        .hwndOwner = null,
        .hInstance = null,
        .lpstrFilter = "SIE Files (*.sie)\x00*.sie\x00All Files (*.*)\x00*.*\x00",
        .lpstrCustomFilter = null,
        .nMaxCustFilter = 0,
        .nFilterIndex = 1,
        .lpstrFile = file_buf.ptr,
        .nMaxFile = BUF_LEN,
        .lpstrFileTitle = null,
        .nMaxFileTitle = 0,
        .lpstrInitialDir = null,
        .lpstrTitle = "Select SIE File(s)",
        // OFN_ALLOWMULTISELECT | OFN_EXPLORER | OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR
        .flags = 0x00081808 | 0x00000200,
        .nFileOffset = 0,
        .nFileExtension = 0,
        .lpstrDefExt = "sie",
        .lCustData = 0,
        .lpfnHook = null,
        .lpTemplateName = null,
        .pvReserved = null,
        .dwReserved = 0,
        .flagsEx = 0,
    };
    if (GetOpenFileNameA(&ofn) == 0) return &[_][]const u8{};

    // Parse result: if lpstrFile contains only one null-terminated string with no
    // second null immediately after, it's a single full path.
    // Otherwise: directory\0file1\0file2\0...\0\0
    var result = std.ArrayListUnmanaged([]const u8){};
    errdefer {
        for (result.items) |p| allocator.free(p);
        result.deinit(allocator);
    }

    const first_len = std.mem.indexOfScalar(u8, file_buf, 0) orelse 0;
    if (first_len == 0) return &[_][]const u8{};

    if (file_buf[first_len + 1] == 0) {
        // Single file — the full path is in file_buf[0..first_len]
        try result.append(allocator, try allocator.dupe(u8, file_buf[0..first_len]));
    } else {
        // Multiple files — first token is directory
        const dir = file_buf[0..first_len];
        var pos: usize = first_len + 1;
        while (pos < BUF_LEN) {
            const fname_len = std.mem.indexOfScalar(u8, file_buf[pos..], 0) orelse break;
            if (fname_len == 0) break; // double null = end
            const fname = file_buf[pos .. pos + fname_len];
            const full = try std.fmt.allocPrint(allocator, "{s}\\{s}", .{ dir, fname });
            try result.append(allocator, full);
            pos += fname_len + 1;
        }
    }

    return try result.toOwnedSlice(allocator);
}

// Shell browse-for-folder structures
const BROWSEINFOA = extern struct {
    hwndOwner: ?*anyopaque,
    pidlRoot: ?*anyopaque,
    pszDisplayName: ?[*]u8,
    lpszTitle: ?[*:0]const u8,
    ulFlags: u32,
    lpfn: ?*anyopaque,
    lParam: usize,
    iImage: i32,
};
extern "shell32" fn SHBrowseForFolderA(lpbi: *BROWSEINFOA) ?*anyopaque;
extern "shell32" fn SHGetPathFromIDListA(pidl: *anyopaque, pszPath: [*]u8) c_int;
extern "ole32" fn CoTaskMemFree(pv: ?*anyopaque) void;

// ── Modern Explorer-style folder picker (IFileOpenDialog) ───────────────
// Uses the Common Item Dialog API (Vista+) for the same look and feel as the
// "Open" / "Save As" dialogs in File Explorer. Falls back to the legacy
// SHBrowseForFolder tree dialog if anything fails.

const GUID = extern struct {
    Data1: u32,
    Data2: u16,
    Data3: u16,
    Data4: [8]u8,
};

const CLSID_FileOpenDialog = GUID{
    .Data1 = 0xDC1C5A9C,
    .Data2 = 0xE88A,
    .Data3 = 0x4DDE,
    .Data4 = .{ 0xA5, 0xA1, 0x60, 0xF8, 0x2A, 0x20, 0xAE, 0xF7 },
};
const IID_IFileOpenDialog = GUID{
    .Data1 = 0xD57C7288,
    .Data2 = 0xD4AD,
    .Data3 = 0x4768,
    .Data4 = .{ 0xBE, 0x02, 0x9D, 0x96, 0x95, 0x32, 0xD9, 0x60 },
};

const FOS_PICKFOLDERS: u32 = 0x20;
const FOS_FORCEFILESYSTEM: u32 = 0x40;
const SIGDN_FILESYSPATH: u32 = 0x80058000;
const CLSCTX_INPROC_SERVER: u32 = 0x1;
const S_OK: i32 = 0;

extern "ole32" fn CoCreateInstance(
    rclsid: *const GUID,
    pUnkOuter: ?*anyopaque,
    dwClsContext: u32,
    riid: *const GUID,
    ppv: *?*anyopaque,
) i32;

// Minimal vtables — only the slots we actually call. Other slots are typed as
// opaque pointers so the layout stays correct.
const IShellItemVtbl = extern struct {
    QueryInterface: *const anyopaque,
    AddRef: *const anyopaque,
    Release: *const fn (this: *anyopaque) callconv(.winapi) u32,
    BindToHandler: *const anyopaque,
    GetParent: *const anyopaque,
    GetDisplayName: *const fn (this: *anyopaque, sigdnName: u32, ppszName: *?[*:0]u16) callconv(.winapi) i32,
    GetAttributes: *const anyopaque,
    Compare: *const anyopaque,
};
const IShellItem = extern struct { lpVtbl: *const IShellItemVtbl };

const IFileOpenDialogVtbl = extern struct {
    // IUnknown
    QueryInterface: *const anyopaque,
    AddRef: *const anyopaque,
    Release: *const fn (this: *anyopaque) callconv(.winapi) u32,
    // IModalWindow
    Show: *const fn (this: *anyopaque, hwndOwner: ?*anyopaque) callconv(.winapi) i32,
    // IFileDialog
    SetFileTypes: *const anyopaque,
    SetFileTypeIndex: *const anyopaque,
    GetFileTypeIndex: *const anyopaque,
    Advise: *const anyopaque,
    Unadvise: *const anyopaque,
    SetOptions: *const fn (this: *anyopaque, fos: u32) callconv(.winapi) i32,
    GetOptions: *const anyopaque,
    SetDefaultFolder: *const anyopaque,
    SetFolder: *const anyopaque,
    GetFolder: *const anyopaque,
    GetCurrentSelection: *const anyopaque,
    SetFileName: *const anyopaque,
    GetFileName: *const anyopaque,
    SetTitle: *const fn (this: *anyopaque, pszTitle: [*:0]const u16) callconv(.winapi) i32,
    SetOkButtonLabel: *const anyopaque,
    SetFileNameLabel: *const anyopaque,
    GetResult: *const fn (this: *anyopaque, ppsi: *?*IShellItem) callconv(.winapi) i32,
    AddPlace: *const anyopaque,
    SetDefaultExtension: *const anyopaque,
    Close: *const anyopaque,
    SetClientGuid: *const anyopaque,
    ClearClientData: *const anyopaque,
    SetFilter: *const anyopaque,
    // IFileOpenDialog
    GetResults: *const anyopaque,
    GetSelectedItems: *const anyopaque,
};
const IFileOpenDialog = extern struct { lpVtbl: *const IFileOpenDialogVtbl };

extern "kernel32" fn WideCharToMultiByte(
    CodePage: u32,
    dwFlags: u32,
    lpWideCharStr: [*]const u16,
    cchWideChar: c_int,
    lpMultiByteStr: ?[*]u8,
    cbMultiByte: c_int,
    lpDefaultChar: ?[*]const u8,
    lpUsedDefaultChar: ?*c_int,
) c_int;
const CP_UTF8: u32 = 65001;

fn browseFolder(allocator: std.mem.Allocator) ?[]const u8 {
    _ = CoInitializeEx(null, 0x2); // COINIT_APARTMENTTHREADED

    var raw: ?*anyopaque = null;
    if (CoCreateInstance(&CLSID_FileOpenDialog, null, CLSCTX_INPROC_SERVER, &IID_IFileOpenDialog, &raw) != S_OK) {
        return browseFolderLegacy(allocator);
    }
    const dlg: *IFileOpenDialog = @ptrCast(@alignCast(raw.?));
    defer _ = dlg.lpVtbl.Release(dlg);

    _ = dlg.lpVtbl.SetOptions(dlg, FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM);

    // Title (UTF-16, null-terminated).
    const title_w = [_:0]u16{ 'S', 'e', 'l', 'e', 'c', 't', ' ', 'O', 'u', 't', 'p', 'u', 't', ' ', 'F', 'o', 'l', 'd', 'e', 'r' };
    _ = dlg.lpVtbl.SetTitle(dlg, &title_w);

    if (dlg.lpVtbl.Show(dlg, null) != S_OK) return null; // user cancelled or error

    var item_raw: ?*IShellItem = null;
    if (dlg.lpVtbl.GetResult(dlg, &item_raw) != S_OK) return null;
    const item = item_raw orelse return null;
    defer _ = item.lpVtbl.Release(item);

    var wpath: ?[*:0]u16 = null;
    if (item.lpVtbl.GetDisplayName(item, SIGDN_FILESYSPATH, &wpath) != S_OK) return null;
    const wp = wpath orelse return null;
    defer CoTaskMemFree(@ptrCast(wp));

    // UTF-16 → UTF-8
    const wlen: c_int = blk: {
        var n: usize = 0;
        while (wp[n] != 0) : (n += 1) {}
        break :blk @intCast(n);
    };
    if (wlen == 0) return null;
    const need = WideCharToMultiByte(CP_UTF8, 0, wp, wlen, null, 0, null, null);
    if (need <= 0) return null;
    const buf = allocator.alloc(u8, @intCast(need)) catch return null;
    const written = WideCharToMultiByte(CP_UTF8, 0, wp, wlen, buf.ptr, need, null, null);
    if (written <= 0) {
        allocator.free(buf);
        return null;
    }
    return buf;
}

fn browseFolderLegacy(allocator: std.mem.Allocator) ?[]const u8 {
    _ = CoInitializeEx(null, 0x2);
    var display: [260]u8 = [_]u8{0} ** 260;
    var bi = BROWSEINFOA{
        .hwndOwner = null,
        .pidlRoot = null,
        .pszDisplayName = &display,
        .lpszTitle = "Select Output Folder",
        .ulFlags = 0x0041, // BIF_RETURNONLYFSDIRS | BIF_NEWDIALOGSTYLE
        .lpfn = null,
        .lParam = 0,
        .iImage = 0,
    };
    const pidl = SHBrowseForFolderA(&bi) orelse return null;
    defer CoTaskMemFree(pidl);
    var path_buf: [260]u8 = [_]u8{0} ** 260;
    if (SHGetPathFromIDListA(pidl, &path_buf) == 0) return null;
    const len = std.mem.indexOfScalar(u8, &path_buf, 0) orelse return null;
    if (len == 0) return null;
    return allocator.dupe(u8, path_buf[0..len]) catch null;
}

// ── Drawing helpers ───────────────────────────────────────────────────────

/// Load persisted format-selection state from `%APPDATA%\ExportSIE\config.bin`.
/// Silent on any error — the GUI just starts with the default (none selected).
fn loadConfig(app: *AppState) void {
    const dir = std.fs.getAppDataDir(app.allocator, "ExportSIE") catch return;
    defer app.allocator.free(dir);
    const path = std.fs.path.join(app.allocator, &.{ dir, "config.bin" }) catch return;
    defer app.allocator.free(path);
    const file = std.fs.openFileAbsolute(path, .{}) catch return;
    defer file.close();
    var buf: [NUM_FORMATS]u8 = undefined;
    const n = file.readAll(&buf) catch return;
    if (n < NUM_FORMATS) return;
    for (0..NUM_FORMATS) |i| app.format_selected[i] = buf[i] != 0;
}

/// Persist the current format-selection state. Best-effort; failures are
/// swallowed because losing the preference is not worth crashing on shutdown.
fn saveConfig(app: *AppState) void {
    const dir = std.fs.getAppDataDir(app.allocator, "ExportSIE") catch return;
    defer app.allocator.free(dir);
    std.fs.makeDirAbsolute(dir) catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => return,
    };
    const path = std.fs.path.join(app.allocator, &.{ dir, "config.bin" }) catch return;
    defer app.allocator.free(path);
    const file = std.fs.createFileAbsolute(path, .{ .truncate = true }) catch return;
    defer file.close();
    var buf: [NUM_FORMATS]u8 = undefined;
    for (0..NUM_FORMATS) |i| buf[i] = if (app.format_selected[i]) 1 else 0;
    file.writeAll(&buf) catch {};
}

/// Draw a clean check mark centred at (cx, cy). Uses a 3-point linear spline
/// so the bend is rendered as a single joined stroke (no seam at the elbow),
/// with filled circle caps at the endpoints for rounded tips.
/// `scale` is a uniform multiplier (1.0 ≈ ~14 px tall check).
fn drawCheck(cx: f32, cy: f32, scale: f32, color: rl.Color) void {
    const p0 = rl.Vector2{ .x = cx - 6 * scale, .y = cy + 0 * scale };
    const p1 = rl.Vector2{ .x = cx - 1 * scale, .y = cy + 5 * scale };
    const p2 = rl.Vector2{ .x = cx + 7 * scale, .y = cy - 5 * scale };
    const thickness: f32 = 2.2 * scale;
    const cap_r: f32 = thickness * 0.5;
    const pts = [_]rl.Vector2{ p0, p1, p2 };
    rl.drawSplineLinear(&pts, thickness, color);
    // Rounded end caps (the spline already joins cleanly at p1).
    rl.drawCircleV(p0, cap_r, color);
    rl.drawCircleV(p1, cap_r, color);
    rl.drawCircleV(p2, cap_r, color);
}

fn drawFont(loaded: bool, font: rl.Font, text: [:0]const u8, x: i32, y: i32, size: f32, color: rl.Color) void {
    if (loaded) {
        rl.drawTextEx(font, text, .{ .x = @floatFromInt(x), .y = @floatFromInt(y) }, size, 0.5, color);
    } else {
        rl.drawText(text, x, y, @intFromFloat(size), color);
    }
}

fn measureFont(loaded: bool, font: rl.Font, text: [:0]const u8, size: f32) i32 {
    if (loaded) {
        const v = rl.measureTextEx(font, text, size, 0.5);
        return @intFromFloat(v.x);
    } else {
        return rl.measureText(text, @intFromFloat(size));
    }
}

fn applyTheme(theme: *const Theme) void {
    rg.setStyle(.default, .{ .default = .background_color }, theme.rg_bg);
    rg.setStyle(.button, .{ .control = .base_color_normal }, theme.rg_btn_normal);
    rg.setStyle(.button, .{ .control = .text_color_normal }, theme.rg_btn_text);
    rg.setStyle(.button, .{ .control = .border_color_normal }, theme.rg_btn_border);
    rg.setStyle(.button, .{ .control = .base_color_focused }, theme.rg_btn_focused);
    rg.setStyle(.button, .{ .control = .text_color_focused }, theme.rg_btn_focused_text);
    rg.setStyle(.button, .{ .control = .border_color_focused }, theme.rg_btn_focused_border);
    rg.setStyle(.button, .{ .control = .base_color_pressed }, theme.rg_btn_pressed);
    rg.setStyle(.button, .{ .control = .text_color_pressed }, theme.rg_btn_pressed_text);
    rg.setStyle(.button, .{ .control = .border_color_pressed }, theme.rg_btn_pressed_border);
    rg.setStyle(.button, .{ .control = .base_color_disabled }, theme.rg_btn_disabled);
    rg.setStyle(.button, .{ .control = .text_color_disabled }, theme.rg_btn_disabled_text);
    rg.setStyle(.button, .{ .control = .border_color_disabled }, theme.rg_btn_disabled_border);
    rg.setStyle(.button, .{ .control = .border_width }, 1);
    rg.setStyle(.textbox, .{ .control = .base_color_normal }, theme.rg_tb_bg);
    rg.setStyle(.textbox, .{ .control = .border_color_normal }, theme.rg_tb_border);
    rg.setStyle(.textbox, .{ .control = .text_color_normal }, theme.rg_tb_text);
    rg.setStyle(.textbox, .{ .control = .base_color_focused }, theme.rg_tb_focused_bg);
    rg.setStyle(.textbox, .{ .control = .border_color_focused }, theme.rg_tb_focused_border);
    rg.setStyle(.textbox, .{ .control = .text_color_focused }, theme.rg_tb_focused_text);
    rg.setStyle(.textbox, .{ .control = .border_width }, 1);
    rg.setStyle(.label, .{ .control = .text_color_normal }, theme.rg_label_text);
}
