const std = @import("std");
const micronet = @import("micronet");

const SocketType = enum { Server, Client };
const PollRegistry = micronet.PollRegistry(SocketType, 16);

pub fn main() !void {
    var args_iter = std.process.args();

    const exe_name = args_iter.next() orelse return error.MissingArgument;
    _ = exe_name;
    const port_name = args_iter.next() orelse return error.MissingArgument;
    const port_number = try std.fmt.parseInt(u16, port_name, 10);
    const res = micronet.add(2, 4);
    const addr = try std.net.Ip4Address.parse("127.0.0.1", port_number);
    if (micronet.create_tcp_sock(addr)) |socket| {
        // _ = sock;
        std.debug.print("port#={d}, result is 0x{x}\n", .{ port_number, res });
        const stdin = std.io.getStdIn().reader();
        var registry = try PollRegistry.init(16);

        try registry.register(.Server, socket.fd, micronet.PollEvent.READ);

        
        var buf: [16]u8 = undefined;
        _ = try stdin.readUntilDelimiterOrEof(buf[0..], '\n');
        if (socket.accept()) |client| {
            std.debug.print("client connected {}", .{client.addr});
        } else |err| {
            std.debug.print("accept error  {} \n", .{err});
        }
        _ = try stdin.readUntilDelimiterOrEof(buf[0..], '\n');
    } else |err| {
        std.debug.print("error creating sock {} \n", .{err});
    }
}
