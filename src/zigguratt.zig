const std = @import("std");
const fs = std.fs;

const c = @cImport(@cInclude("termios.h"));

// https://github.com/zigtools/zls/blob/master/src/lsp.zig#L77-L99
pub fn UnionParser(comptime T: type) type {
    return struct {
        pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(source.*))!T {
            const json_value = try std.json.Value.jsonParse(allocator, source, options);
            return try jsonParseFromValue(allocator, json_value, options);
        }

        pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) std.json.ParseFromValueError!T {
            inline for (std.meta.fields(T)) |field| {
                if (std.json.parseFromValueLeaky(field.type, allocator, source, options)) |result| {
                    return @unionInit(T, field.name, result);
                } else |_| {}
            }
            return error.Overflow;
        }

        pub fn jsonStringify(self: T, stream: anytype) @TypeOf(stream.*).Error!void {
            switch (self) {
                inline else => |value| try stream.write(value),
            }
        }
    };
}

pub const Bus = struct {
    file: fs.File,
    pub fn close(self: Bus) void {
        //Close the file
        self.file.close();
    }

    pub const DeviceListElement = struct {
        deviceId: []const u8,
        typeNames: []const []const u8,
    };

    ///Gets a list of all devices, caller owns returned value
    pub fn getList(self: Bus, allocator: std.mem.Allocator) !RequestReturnType([]const DeviceListElement) {
        var section = beginProfileSection(@src());
        defer section.endProfileSection();

        // std.debug.print("requesting\n", .{});
        const ans = try self.request(allocator, "{\"type\":\"list\"}", "list", []const DeviceListElement);
        // std.debug.print("ans: {}\n", .{ans});

        return ans;
    }

    pub fn findDevice(bus: Bus, allocator: std.mem.Allocator, device_type: DeviceType) !Device {
        var section = beginProfileSection(@src());
        defer section.endProfileSection();

        const list = try bus.getList(allocator);
        defer list.deinit();

        // std.debug.print("got list\n", .{});

        if (list.value.data) |parsed| {
            for (parsed) |device| {
                for (device.typeNames) |name| {
                    // std.debug.print("device name type: {s}\n", .{name});
                    if (std.mem.eql(u8, name, @tagName(device_type))) {
                        return .{
                            .bus = bus,
                            .type = device_type,
                            .name = try allocator.dupe(u8, name),
                            .id = try allocator.dupe(u8, device.deviceId),
                            .allocator = allocator,
                        };
                    }
                }
            }
        } else {
            return error.MissingDataField;
        }

        return error.DeviceNotFound;
    }

    fn ResponseStruct(comptime DataType: type) type {
        return struct {
            type: []const u8,
            data: ?DataType = null,
        };
    }

    pub fn RequestReturnType(comptime DataType: type) type {
        return std.json.Parsed(ResponseStruct(DataType));
    }

    ///Caller owns returned data
    pub fn request(self: Bus, allocator: std.mem.Allocator, body: []const u8, expected_response_type: []const u8, comptime DataType: type) !RequestReturnType(DataType) {
        var section = beginProfileSection(@src());
        defer section.endProfileSection();
        // std.debug.print("writing {s}\n", .{body});
        //write the body to the file
        try self.writeData(body);

        // std.debug.print("reading\n", .{});

        //Read the raw response
        const response_raw = try self.readData(allocator);
        defer allocator.free(response_raw);

        const ResponseType = ResponseStruct(DataType);

        // std.debug.print("got response: {s} parsing it as {s}\n", .{ response_raw, @typeName(ResponseType) });

        //Parse the response
        const parsed = try std.json.parseFromSlice(
            ResponseType,
            allocator,
            response_raw,
            .{
                .allocate = .alloc_always,
                .ignore_unknown_fields = true,
            },
        );
        errdefer parsed.deinit();

        //If its an error
        if (std.mem.eql(u8, parsed.value.type, "error")) {
            return error.ErrorResponse;
        }

        //If the type is wrong
        if (!std.mem.eql(u8, expected_response_type, parsed.value.type)) {
            return error.IncorrectResponseType;
        }

        return parsed;
    }

    fn writeData(self: Bus, body: []const u8) !void {
        var writer = self.file.writer();

        try writer.writeByte(0); //start delimiter
        try writer.writeAll(body);
        try writer.writeByte(0); //end delimiter
    }
    ///Reads data from the bus, caller owns returned memory
    fn readData(self: Bus, allocator: std.mem.Allocator) ![]const u8 {
        var section = beginProfileSection(@src());
        defer section.endProfileSection();

        // std.debug.print("reading...\n", .{});

        var reader = self.file.reader();

        var searching_for_header = true;
        while (searching_for_header) {
            const b = reader.readByte() catch |err| {
                if (err != error.WouldBlock) {
                    return err;
                }

                continue;
            };

            if (b == 0) {
                searching_for_header = false;
            }
        }

        //read the header null byte
        const capacity: usize = 2048;

        //Init a new list
        var result = std.ArrayList(u8).init(allocator);
        //ensure it can store 2048 bytes
        try result.ensureTotalCapacity(capacity);

        var end_found: bool = false;
        while (!end_found) {
            //ensure there is at least 2048 bytes available in the buffer
            try result.ensureUnusedCapacity(capacity);

            //read as many bytes as possible into the buffer
            const read: usize = reader.read(result.allocatedSlice()[result.items.len..]) catch |err| {
                if (!std.mem.eql(u8, @errorName(err), "WouldBlock"))
                    return err;

                //If we would block
                continue;
            };

            try result.resize(result.items.len + read);

            //If the last byte in the array is a null byte, then we have reached the end
            if (result.items[result.items.len - 1] == 0) {
                end_found = true;
                //Remove the null byte from the end of the list
                result.items.len -= 1;
            }
        }

        return result.toOwnedSlice();
    }
};

pub const DeviceType = enum {
    file_import_export,
    redstone,
};

pub const Device = struct {
    type: DeviceType,
    bus: Bus,
    id: []const u8,
    name: []const u8,
    allocator: std.mem.Allocator,
    pub fn deinit(self: Device) void {
        self.allocator.free(self.id);
        self.allocator.free(self.name);
    }

    pub const InvokeDataParameter = union(enum) {
        pub usingnamespace UnionParser(@This());

        number: usize,
        string: []const u8,
        bytes: []f64, //byte arrays are serialized as an array of doubles, because.... JSON!!!
    };

    const InvokeData = struct {
        deviceId: []const u8,
        name: []const u8,
        parameters: []const InvokeDataParameter,
    };

    const InvokeRequest = Request(InvokeData);

    pub fn invoke(
        self: Device,
        allocator: std.mem.Allocator,
        method: []const u8,
        parameters: []const InvokeDataParameter,
        comptime ResponseDataType: type,
    ) !Bus.RequestReturnType(ResponseDataType) {
        var section = beginProfileSection(@src());
        defer section.endProfileSection();

        const request: InvokeRequest = InvokeRequest{
            .type = "invoke",
            .data = InvokeData{
                .deviceId = self.id,
                .name = method,
                .parameters = parameters,
            },
        };

        //Turn the request into a JSON string
        const stringified_request = try std.json.stringifyAlloc(allocator, request, .{});
        defer allocator.free(stringified_request);

        //Send the request to the device, and get the response
        const response = try self.bus.request(
            allocator,
            stringified_request,
            "result",
            ResponseDataType,
        );

        return response;
    }
};

fn Request(comptime DataType: type) type {
    return struct {
        type: []const u8,
        data: DataType,
    };
}

pub fn openBus() !Bus {
    var section = beginProfileSection(@src());
    defer section.endProfileSection();

    var bus: Bus = undefined;

    var file = try fs.openFileAbsolute("/dev/hvc0", .{ .mode = .read_write });
    errdefer file.close();

    _ = std.os.linux.fcntl(
        file.handle,
        @as(i32, @intCast(std.os.F.SETFL)),
        @as(
            usize,
            @intCast(std.os.linux.fcntl(file.handle, @as(i32, @intCast(std.os.F.GETFL)), @as(usize, 0)) | @as(usize, @intCast(std.os.O.NONBLOCK))),
        ),
    );

    var termios: c.termios = undefined;
    if (c.tcgetattr(file.handle, &termios) != 0) return error.FailedToGetTerminalAttributes;
    c.cfmakeraw(&termios);
    if (c.tcsetattr(file.handle, @intFromEnum(std.os.TCSA.NOW), &termios) != 0) return error.FailedToSetTerminalAttributes;

    bus.file = file;

    return bus;
}

pub const ProfileSection = struct {
    name: []const u8,
    start: i64,
    pub fn endProfileSection(self: ProfileSection) void {
        _ = self;
        //uncomment to enable profiling
        // std.debug.print("Profile {s} took {d}ms\n", .{ self.name, std.time.milliTimestamp() - self.start });
    }
};

pub fn beginProfileSection(comptime file: std.builtin.SourceLocation) ProfileSection {
    return .{ .name = file.fn_name, .start = std.time.milliTimestamp() };
}

pub fn beginProfileSectionManual(comptime name: []const u8) ProfileSection {
    return .{ .name = name, .start = std.time.milliTimestamp() };
}
