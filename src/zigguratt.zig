const std = @import("std");
const fs = std.fs;

const c = @cImport(@cInclude("termios.h"));

pub const Bus = struct {
    file: fs.File,
    pub fn close(self: Bus) void {
        //Close the file
        self.file.close();
    }
    ///Gets a list of all devices, caller owns returned ValueTree
    pub fn getList(self: Bus, allocator: std.mem.Allocator) !std.json.ValueTree {
        var parser = std.json.Parser.init(allocator, true);
        defer parser.deinit();

        std.debug.print("requesting\n", .{});
        var ans = try self.request(allocator, &parser, "{\"type\":\"list\"}", "list");

        return ans;
    }
    pub fn findDevice(bus: Bus, allocator: std.mem.Allocator, device_type: DeviceType) !Device {
        var list = try bus.getList(allocator);
        defer list.deinit();

        var data: std.json.Array = (list.root.Object.get("data") orelse unreachable).Array;
        for (data.items) |itema| {
            var item: std.json.Value = itema;
            var typeNames: std.json.Array = (item.Object.get("typeNames") orelse return error.NoTypeNamesInJson).Array;

            for (typeNames.items) |namea| {
                var name: std.json.Value = namea;
                if (std.mem.eql(u8, name.String, @tagName(device_type))) {
                    return .{
                        .bus = bus,
                        .type = device_type,
                        .name = try allocator.dupe(u8, name.String),
                        .id = try allocator.dupe(u8, (item.Object.get("deviceId") orelse return error.NoDeviceIdInJson).String),
                        .allocator = allocator,
                    };
                }
            }
        }

        return error.DeviceNotFound;
    }

    ///Caller owns returned ValueTree
    pub fn request(self: Bus, allocator: std.mem.Allocator, parser: *std.json.Parser, body: []const u8, expected_response_type: []const u8) !std.json.ValueTree {
        std.debug.print("writing\n", .{});
        //write the body to the file
        try self.writeData(body);

        if (parser.copy_strings == false) {
            return error.ParserDoesNotCopyStrings;
        }

        std.debug.print("reading\n", .{});
        //Read the raw response
        var response_raw = try self.readData(allocator);
        defer allocator.free(response_raw);
        std.debug.print("parsing\n", .{});
        //Parse the response
        var response = try parser.parse(response_raw);

        //Get the response type
        var response_type_value: std.json.Value = response.root.Object.get("type") orelse return error.NoResponseType;
        var response_type = response_type_value.String;

        //If its an error
        if (std.mem.eql(u8, response_type, "error")) {
            return error.GotErrorResponse;
        }

        //If the type is wrong
        if (!std.mem.eql(u8, expected_response_type, response_type)) {
            return error.GotIncorrectResponseType;
        }

        if (response.root.Object.get("data") == null) return error.NoResponseData;

        return response;
    }
    fn writeData(self: Bus, body: []const u8) !void {
        var writer = self.file.writer();

        try writer.writeByte(0); //start delimiter
        try writer.writeAll(body);
        try writer.writeByte(0); //end delimiter
    }
    ///Reads data from the bus, caller owns returned memory
    fn readData(self: Bus, allocator: std.mem.Allocator) ![]const u8 {
        var reader = self.file.reader();

        if (try reader.readByte() == 0) {
            var len: usize = 0;
            var capacity: usize = 1024;
            var result = try allocator.alloc(u8, capacity);

            var b: u8 = try reader.readByte();
            while (b != 0) {
                result[len] = b;
                len += 1;

                if (len >= capacity) {
                    capacity += 1024;
                    //Allocate a new array
                    var new = try allocator.alloc(u8, 1024);
                    //Copy the old data into the new array
                    std.mem.copy(u8, new, result);
                    //Free the old data
                    allocator.free(result);
                    result = new;
                }

                b = try reader.readByte();
            }

            return result[0..len];
        }

        //if no data was read, return 0
        return &.{};
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
        bytes: []const u8,
    };

    const InvokeData = struct {
        deviceId: []const u8,
        name: []const u8,
        parameters: []InvokeDataParameter,
    };

    const InvokeRequest = Request(InvokeData);

    pub fn invoke(self: Device, allocator: std.mem.Allocator, method: []const u8, parameters: []InvokeDataParameter) !void {
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

        //Send the request to the FIEC, and get the response
        var response = try self.bus.request(allocator, parser, stringified_request, "result");
        defer response.deinit();

        //TODO: handle the response here
    }
};

fn Request(comptime DataType: type) type {
    return struct {
        type: []const u8,
        data: DataType,
    };
}

pub fn openBus() !Bus {
    var bus: Bus = undefined;

    var file = try fs.openFileAbsolute("/dev/hvc0", .{ .mode = .read_write });
    errdefer file.close();

    var termios: c.termios = undefined;
    if (c.tcgetattr(file.handle, &termios) != 0) return error.FailedToGetTerminalAttributes;
    c.cfmakeraw(&termios);
    if (c.tcsetattr(file.handle, @enumToInt(std.os.TCSA.NOW), &termios) != 0) return error.FailedToSetTerminalAttributes;

    bus.file = file;

    return bus;
}
