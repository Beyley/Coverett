const std = @import("std");
const zigguratt = @import("zigguratt.zig");

pub fn main() !void {
    //Create our allocater
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) @panic("leak.");

    //Open the bus
    var bus = try zigguratt.openBus();
    defer bus.close();

    //Find the import/export card
    var device = try bus.findDevice(gpa.allocator(), zigguratt.DeviceType.file_import_export);
    defer device.deinit();
    std.debug.print("found device id {s}, with type {s}\n", .{ device.id, @tagName(device.type) });
}
