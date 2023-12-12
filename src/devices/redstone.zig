const std = @import("std");
const zigguratt = @import("../zigguratt.zig");

const Redstone = @This();

pub const Side = enum {
    north,
    south,
    east,
    west,
    up,
    down,
};

device: zigguratt.Device,
allocator: std.mem.Allocator,

pub fn createFrom(device: zigguratt.Device, allocator: std.mem.Allocator) !Redstone {
    if (device.type != .redstone) {
        return error.IncorrectDeviceType;
    }

    return .{ .device = device, .allocator = allocator };
}

pub fn getRedstoneInput(redstone_interface: Redstone, side: Side) !u4 {
    const ret = try redstone_interface.device.invoke(
        redstone_interface.allocator,
        "getRedstoneInput",
        &.{.{ .string = @tagName(side) }},
        u4,
    );
    defer ret.deinit();

    return ret.value.data.?;
}

pub fn getRedstoneOutput(redstone_interface: Redstone, side: Side) !u4 {
    const ret = try redstone_interface.device.invoke(
        redstone_interface.allocator,
        "getRedstoneOutput",
        &.{.{ .string = @tagName(side) }},
        u4,
    );
    defer ret.deinit();
    return ret.value.data.?;
}

pub fn setRedstoneOutput(redstone_interface: Redstone, side: Side, value: u4) !void {
    const ret = try redstone_interface.device.invoke(
        redstone_interface.allocator,
        "setRedstoneOutput",
        &.{ .{ .string = @tagName(side) }, .{ .number = value } },
        struct {},
    );
    defer ret.deinit();
}
