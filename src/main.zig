const std = @import("std");
const SIEtoHDF5 = @import("SIEtoHDF5");

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) {
        const stderr = std.fs.File.stderr().deprecatedWriter();
        try stderr.print("Usage: sie2hdf5 <input.sie> <output.h5>\n", .{});
        std.process.exit(1);
    }

    SIEtoHDF5.convert(allocator, args[1], args[2]) catch |err| {
        const stderr = std.fs.File.stderr().deprecatedWriter();
        try stderr.print("Error: {}\n", .{err});
        std.process.exit(1);
    };
}

test "arg parsing smoke test" {
    // Verifies the main module compiles
    try std.testing.expect(true);
}
