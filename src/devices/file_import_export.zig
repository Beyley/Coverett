const std = @import("std");
const zigguratt = @import("../zigguratt.zig");

const FileImportExport = @This();

device: zigguratt.Device,
allocator: std.mem.Allocator,

pub fn createFrom(device: zigguratt.Device, allocator: std.mem.Allocator) !FileImportExport {
    if (device.type != .file_import_export) {
        return error.IncorrectDeviceType;
    }

    return .{ .device = device, .allocator = allocator };
}

pub fn resetTransfer(self: FileImportExport) !void {
    //Invoke the reset method
    const data = try self.device.invoke(self.allocator, "reset", &.{}, struct {});
    defer data.deinit();

    //When the reset is successful, it never sends a `data` parameter, so if it does, something fishy is going on
    if (data.value.data != null) {
        return error.InvalidResetResponse;
    }

    // std.debug.print("reset FIEC transfer\n", .{});
}

pub fn requestFileImport(self: FileImportExport) !void {
    const data = try self.device.invoke(self.allocator, "requestImportFile", &.{}, bool);
    defer data.deinit();

    if (data.value.data) |response| {
        if (!response) {
            return error.NoUsersPresent;
        }
    } else {
        return error.MissingResponseData;
    }

    // std.debug.print("requested file\n", .{});
}

pub const FileInfo = struct {
    pub const FileInfoStatus = enum {
        ok,
        no_file,
        empty,
    };

    status: FileInfoStatus,
    filename: ?[]const u8,
    size: ?usize,
    allocator: std.mem.Allocator,

    pub fn deinit(self: FileInfo) void {
        if (self.filename) |filename| {
            self.allocator.free(filename);
        }
    }
};

pub const BeginFileImportErrors = error{
    ImportCancelled,
    InvalidState,
};

///Begins a file import, caller owns returned memory
pub fn beginFileImport(self: FileImportExport, allocator: std.mem.Allocator) !FileInfo {
    const ResponseData = union(enum) {
        pub usingnamespace zigguratt.UnionParser(@This());

        file: struct {
            name: []const u8,
            size: usize,
        },
        error_string: []const u8,
    };

    const data = try self.device.invoke(self.allocator, "beginImportFile", &.{}, ResponseData);
    defer data.deinit();

    if (data.value.data) |parsed| {
        switch (parsed) {
            .error_string => |error_string| {
                if (std.mem.eql(u8, error_string, "import was canceled")) {
                    return BeginFileImportErrors.ImportCancelled;
                } else if (std.mem.eql(u8, error_string, "invalid state")) {
                    return BeginFileImportErrors.InvalidState;
                }
            },
            .file => |file| {
                return .{ .status = .ok, .filename = try allocator.dupe(u8, file.name), .size = file.size, .allocator = allocator };
            },
        }
    } else {
        return .{ .status = .no_file, .filename = null, .size = null, .allocator = allocator };
    }

    unreachable;
}

///Reads data from a file import, returns an empty array if the file is done
/// caller owns returned memory
pub fn fileImportRead(self: FileImportExport, allocator: std.mem.Allocator) ![]const u8 {
    var section = zigguratt.beginProfileSection(@src());
    defer section.endProfileSection();

    const response_data = try self.device.invoke(self.allocator, "readImportFile", &.{}, []const u8);
    defer response_data.deinit();

    if (response_data.value.data) |data| {
        return allocator.dupe(u8, data);
    } else {
        //If theres no data, return an empty array
        return &.{};
    }
}
