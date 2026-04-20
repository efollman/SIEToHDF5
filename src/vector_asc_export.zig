/// Vector CANalyzer/CANoe ASCII (.asc) exporter — writes raw CAN channels
/// from a SIE file into the line-oriented format consumed by Vector tools.
///
/// Behavior:
/// - Only channels whose `data_type` (or `somat:data_format`) is `message_can`
///   are exported. Non-CAN channels are ignored.
/// - If the SIE file has zero CAN channels the output file is NOT created.
/// - Multiple CAN channels are merged into a single sorted stream and each is
///   emitted with its own 1-based Vector channel number to preserve the source
///   distinction (Vector convention).
///
/// SoMat raw CAN payload layout (per row, variable size 4..12 bytes):
///   bytes[0..4]  big-endian 32-bit ID; bit 31 set = extended (29-bit) frame
///   bytes[4..]   0..8 CAN data bytes (DLC = total_size - 4)
const std = @import("std");
const libsie = @import("libsie");

const SieFile = libsie.sie_file.SieFile;
const Tag = libsie.tag.Tag;

const MAX_DATA: usize = 8;

const Frame = struct {
    ts: f64,
    ch_no: u8,
    id: u32,
    ext: bool,
    dlc: u8,
    data: [MAX_DATA]u8,
};

pub fn convert(allocator: std.mem.Allocator, input_path: [:0]const u8, output_path: [:0]const u8) !void {
    var sf = try SieFile.open(allocator, input_path);
    defer sf.deinit();

    // ── First pass: discover CAN channels and their (test_idx, ch_idx) refs ──
    var can_channels: std.ArrayList(struct { test_i: usize, ch_i: usize, ch_no: u8 }) = .empty;
    defer can_channels.deinit(allocator);

    const tests = sf.getTests();
    for (tests, 0..) |*test_obj, ti| {
        const channels = test_obj.getChannels();
        for (channels, 0..) |*ch, ci| {
            if (!isCanChannel(ch.getTags())) continue;
            const next_no: u8 = @intCast(can_channels.items.len + 1);
            try can_channels.append(allocator, .{ .test_i = ti, .ch_i = ci, .ch_no = next_no });
        }
    }
    if (can_channels.items.len == 0) return; // No CAN data → no file

    // ── Second pass: stream frames into a merged in-memory list ──
    var frames: std.ArrayList(Frame) = .empty;
    defer frames.deinit(allocator);

    for (can_channels.items) |entry| {
        const test_obj = &tests[entry.test_i];
        const ch = &test_obj.getChannels()[entry.ch_i];

        var spig = sf.attachSpigot(ch) catch continue;
        defer spig.deinit();

        while (try spig.get()) |out| {
            for (0..out.num_rows) |row| {
                const ts = out.getFloat64(0, row) orelse continue;
                const raw = out.getRaw(1, row) orelse continue;
                const size: usize = @intCast(raw.size);
                if (size < 4) continue; // Need at least the ID
                const bytes = raw.ptr[0..size];

                const id_be: u32 = (@as(u32, bytes[0]) << 24) |
                    (@as(u32, bytes[1]) << 16) |
                    (@as(u32, bytes[2]) << 8) |
                    @as(u32, bytes[3]);
                const ext = (id_be & 0x8000_0000) != 0;
                const id_masked: u32 = if (ext) id_be & 0x1FFF_FFFF else id_be & 0x7FF;

                var fr = Frame{
                    .ts = ts,
                    .ch_no = entry.ch_no,
                    .id = id_masked,
                    .ext = ext,
                    .dlc = 0,
                    .data = [_]u8{0} ** MAX_DATA,
                };
                const dlc_actual = @min(size - 4, MAX_DATA);
                fr.dlc = @intCast(dlc_actual);
                @memcpy(fr.data[0..dlc_actual], bytes[4 .. 4 + dlc_actual]);

                try frames.append(allocator, fr);
            }
        }
    }

    if (frames.items.len == 0) return; // CAN channels existed but were empty

    // ── Sort merged frames by timestamp (stable within tied timestamps) ──
    std.mem.sort(Frame, frames.items, {}, lessThanByTs);

    // ── Write the .asc file ──
    const out_file = try std.fs.cwd().createFile(output_path, .{});
    defer out_file.close();
    var write_buf: [16 * 1024]u8 = undefined;
    var fw = out_file.writer(&write_buf);
    const w = &fw.interface;

    // Header: pull start_time from file or first test, fall back to "now".
    var date_buf: [64]u8 = undefined;
    const date_str = formatHeaderDate(&date_buf, sf.getFileTags(), tests);
    try w.print("date {s}\n", .{date_str});
    try w.print("base hex  timestamps absolute\n", .{});
    try w.print("internal events logged\n", .{});
    try w.print("// version 11.0.0\n", .{});
    try w.print("Begin Triggerblock {s}\n", .{date_str});

    // First-frame timestamp anchors the relative "Start of measurement" line.
    const t0 = frames.items[0].ts;
    try w.print("   {d:.6} Start of measurement\n", .{0.0});
    _ = t0;

    for (frames.items) |fr| {
        // Time, channel, ID (with optional 'x' for extended), direction, DLC,
        // payload bytes (uppercase hex, space-separated).
        try w.print("   {d:.6} {d}  ", .{ fr.ts, fr.ch_no });
        if (fr.ext) {
            try w.print("{X}x", .{fr.id});
        } else {
            try w.print("{X}", .{fr.id});
        }
        try w.print("             Rx   d {d}", .{fr.dlc});
        for (0..fr.dlc) |i| {
            try w.print(" {X:0>2}", .{fr.data[i]});
        }
        try w.print("\n", .{});
    }

    try w.print("End TriggerBlock\n", .{});
    try w.flush();
}

fn lessThanByTs(_: void, a: Frame, b: Frame) bool {
    return a.ts < b.ts;
}

fn isCanChannel(tags: []const Tag) bool {
    for (tags) |*tag| {
        const id = tag.getId();
        if (std.mem.eql(u8, id, "data_type") or std.mem.eql(u8, id, "somat:data_format")) {
            const v = tag.getString() orelse continue;
            if (std.mem.eql(u8, v, "message_can")) return true;
        }
    }
    return false;
}

fn findTag(tags: []const Tag, key: []const u8) ?[]const u8 {
    for (tags) |*tag| {
        if (std.mem.eql(u8, tag.getId(), key)) return tag.getString();
    }
    return null;
}

/// Build the Vector-style date string. Tries to parse the SIE start_time
/// (ISO 8601: "YYYY-MM-DDTHH:MM:SS[.fffffffff]"). On any failure returns a
/// safe placeholder so the .asc still loads in Vector tools.
fn formatHeaderDate(buf: []u8, file_tags: []const Tag, tests: []const libsie.Test) []const u8 {
    const time_keys = [_][]const u8{ "core:start_time", "start_time", "SIE:start_time", "datetime", "StartTime" };
    var iso: ?[]const u8 = null;
    for (time_keys) |k| if (findTag(file_tags, k)) |v| {
        iso = v;
        break;
    };
    if (iso == null) {
        for (tests) |*t| {
            for (time_keys) |k| if (findTag(t.getTags(), k)) |v| {
                iso = v;
                break;
            };
            if (iso != null) break;
        }
    }

    if (iso) |s| {
        // Expect YYYY-MM-DDTHH:MM:SS[.fff...]
        if (s.len >= 19 and s[4] == '-' and s[7] == '-' and (s[10] == 'T' or s[10] == ' ') and s[13] == ':' and s[16] == ':') {
            const year = std.fmt.parseInt(u16, s[0..4], 10) catch 0;
            const month = std.fmt.parseInt(u8, s[5..7], 10) catch 0;
            const day = std.fmt.parseInt(u8, s[8..10], 10) catch 0;
            const hh = s[11..13];
            const mm = s[14..16];
            const ss = s[17..19];
            // Optional fractional seconds: take up to 3 digits if present.
            var frac: []const u8 = "000";
            if (s.len > 20 and s[19] == '.') {
                const max: usize = @min(s.len - 20, 3);
                frac = s[20 .. 20 + max];
            }
            const dow = dayOfWeek(year, month, day);
            const mon_name = monthName(month);
            const dow_name = dayName(dow);
            return std.fmt.bufPrint(buf, "{s} {s} {d:0>2} {s}:{s}:{s}.{s} {d}", .{
                dow_name, mon_name, day, hh, mm, ss, frac, year,
            }) catch "Mon Jan 01 00:00:00.000 2000";
        }
    }
    return std.fmt.bufPrint(buf, "Mon Jan 01 00:00:00.000 2000", .{}) catch "";
}

/// Zeller's congruence: returns 0=Sunday..6=Saturday for proleptic Gregorian.
fn dayOfWeek(year: u16, month: u8, day: u8) u8 {
    var y: i32 = year;
    var m: i32 = month;
    if (m < 3) {
        m += 12;
        y -= 1;
    }
    const k = @mod(y, 100);
    const j = @divTrunc(y, 100);
    const h = @mod(@as(i32, day) + @divTrunc(13 * (m + 1), 5) + k + @divTrunc(k, 4) + @divTrunc(j, 4) + 5 * j, 7);
    // Zeller: 0=Sat,1=Sun,...,6=Fri → convert to 0=Sun..6=Sat.
    const dow_zeller: u8 = @intCast(@mod(h, 7));
    return (dow_zeller + 6) % 7;
}

fn dayName(d: u8) []const u8 {
    return switch (d) {
        0 => "Sun",
        1 => "Mon",
        2 => "Tue",
        3 => "Wed",
        4 => "Thu",
        5 => "Fri",
        6 => "Sat",
        else => "Mon",
    };
}

fn monthName(m: u8) []const u8 {
    return switch (m) {
        1 => "Jan",
        2 => "Feb",
        3 => "Mar",
        4 => "Apr",
        5 => "May",
        6 => "Jun",
        7 => "Jul",
        8 => "Aug",
        9 => "Sep",
        10 => "Oct",
        11 => "Nov",
        12 => "Dec",
        else => "Jan",
    };
}
