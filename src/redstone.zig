const std = @import("std");
const fs = std.fs;
const zigguratt = @import("zigguratt.zig");

const Redstone = @import("devices/redstone.zig");

pub fn main() !void {
    //Create our allocater
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        _ = gpa.detectLeaks();
        if (gpa.deinit() == .leak) @panic("memory leak!!!");
    }
    const allocator = gpa.allocator();

    const help_text =
        \\{{side}} [output]
        \\Valid sides are up, down, north, south, east, west
        \\
    ;

    if (std.os.argv.len < 2) {
        std.debug.print(help_text, .{});
        return;
    }

    //Open the bus
    var bus = try zigguratt.openBus();
    defer bus.close();

    const device = try bus.findDevice(allocator, .redstone);
    defer device.deinit();

    //Create the card from the device
    var redstone = try Redstone.createFrom(device, allocator);

    const side = std.meta.stringToEnum(Redstone.Side, std.mem.sliceTo(std.os.argv[1], 0)) orelse {
        std.debug.print(help_text, .{});
        return;
    };

    std.debug.print("Side {s} has input of {d}\n", .{ @tagName(side), try redstone.getRedstoneInput(side) });
    std.debug.print("Side {s} has output of {d}\n", .{ @tagName(side), try redstone.getRedstoneOutput(side) });

    if (std.os.argv.len > 2) {
        const value = try std.fmt.parseInt(u4, std.mem.sliceTo(std.os.argv[2], 0), 10);
        std.debug.print("Setting side {s} to {d}\n", .{ @tagName(side), value });
        try redstone.setRedstoneOutput(side, value);
    }
}
