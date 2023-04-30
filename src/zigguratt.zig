const std = @import("std");
const fs = std.fs;

const c = @cImport(@cInclude("termios.h"));

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

        var parser = std.json.Parser.init(allocator, true);
        defer parser.deinit();

        // std.debug.print("requesting\n", .{});
        var ans = try self.request(allocator, &parser, "{\"type\":\"list\"}", "list", []const DeviceListElement);

        return ans;
    }

    pub fn findDevice(bus: Bus, allocator: std.mem.Allocator, device_type: DeviceType) !Device {
        var section = beginProfileSection(@src());
        defer section.endProfileSection();

        var list = try bus.getList(allocator);
        defer std.json.parseFree(@TypeOf(list.parsed), list.parsed, list.parse_options);

        if (list.parsed.data) |parsed| {
            for (parsed) |devicea| {
                var device: DeviceListElement = devicea;

                for (device.typeNames) |namea| {
                    var name: []const u8 = namea;

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
        return struct {
            parsed: ResponseStruct(DataType),
            parse_options: std.json.ParseOptions,
        };
    }

    ///Caller owns returned data
    pub fn request(self: Bus, allocator: std.mem.Allocator, parser: *std.json.Parser, body: []const u8, expected_response_type: []const u8, comptime DataType: type) !RequestReturnType(DataType) {
        var section = beginProfileSection(@src());
        defer section.endProfileSection();
        // std.debug.print("writing\n", .{});
        //write the body to the file
        try self.writeData(body);

        if (parser.copy_strings == false) {
            return error.ParserDoesNotCopyStrings;
        }

        // std.debug.print("reading\n", .{});

        //Read the raw response
        var response_raw = try self.readData(allocator);
        defer allocator.free(response_raw);

        //The options to use when parsing
        var parse_options: std.json.ParseOptions = .{ .allocator = allocator };

        const ResponseType = ResponseStruct(DataType);

        // std.debug.print("got response: {s} parsing it as {s}\n", .{ response_raw, @typeName(DataType) });

        //The token stream of the response
        var tokens = std.json.TokenStream.init(response_raw);
        //Parse the response
        var parsed: ResponseType = try std.json.parse(ResponseType, &tokens, parse_options);
        errdefer std.json.parseFree(ResponseType, parsed, parse_options);

        //If its an error
        if (std.mem.eql(u8, parsed.type, "error")) {
            return error.ErrorResponse;
        }

        //If the type is wrong
        if (!std.mem.eql(u8, expected_response_type, parsed.type)) {
            return error.IncorrectResponseType;
        }

        return .{ .parsed = parsed, .parse_options = parse_options };
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

        var reader = self.file.reader();

        var searching_for_header = true;
        while (searching_for_header) {
            var b = reader.readByte() catch |err| {
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
        var capacity: usize = 2048;

        //Init a new list
        var result = std.ArrayList(u8).init(allocator);
        //ensure it can store 2048 bytes
        try result.ensureTotalCapacity(capacity);

        var end_found: bool = false;
        while (!end_found) {
            //ensure there is at least 2048 bytes available in the buffer
            try result.ensureUnusedCapacity(capacity);

            //read as many bytes as possible into the buffer
            var read: usize = reader.read(result.allocatedSlice()[result.items.len..]) catch |err| {
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

        var request: InvokeRequest = InvokeRequest{
            .type = "invoke",
            .data = InvokeData{
                .deviceId = self.id,
                .name = method,
                .parameters = parameters,
            },
        };

        //Create a JSON parser
        var parser = std.json.Parser.init(allocator, true);
        defer parser.deinit();

        //Turn the request into a JSON string
        var stringified_request = try std.json.stringifyAlloc(allocator, request, .{});
        defer allocator.free(stringified_request);

        //Send the request to the device, and get the response
        var response = try self.bus.request(
            allocator,
            &parser,
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
        @intCast(i32, std.os.F.SETFL),
        @intCast(
            usize,
            std.os.linux.fcntl(file.handle, @intCast(i32, std.os.F.GETFL), @intCast(usize, 0)) | @intCast(usize, std.os.O.NONBLOCK),
        ),
    );

    var termios: c.termios = undefined;
    if (c.tcgetattr(file.handle, &termios) != 0) return error.FailedToGetTerminalAttributes;
    c.cfmakeraw(&termios);
    if (c.tcsetattr(file.handle, @enumToInt(std.os.TCSA.NOW), &termios) != 0) return error.FailedToSetTerminalAttributes;

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
