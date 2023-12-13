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

    const addr = try std.net.Ip4Address.parse("127.0.0.1", port_number);
    const server_sock = try micronet.create_tcp_sock(addr);
    defer std.os.close(server_sock.fd);
    var registry = try PollRegistry.init();

    try registry.register(.Server, server_sock.fd, micronet.PollEvent.READ);
    const timeout_millis = 100;
    while (true) {
        const events = try registry.poll(timeout_millis, &handle_io);
        if (events != 0) {
            std.debug.print("events processed {d}\n", .{events});
        }
    }
}

fn handle_io(registry: *PollRegistry, fd: std.os.fd_t, tag: SocketType, events: micronet.PollEvent) !usize {
    switch (tag) {
        .Server => {
            if (micronet.Socket.accept(fd)) |client_sock| {
                std.debug.print("client connected {}\n", .{client_sock.addr});
                try registry.register(.Client, client_sock.fd, micronet.PollEvent.READ);
            } else |err| {
                std.debug.print("accept error  {} \n", .{err});
            }
        },
        .Client => {
            std.debug.print("event on client socket {d}, {}\n", .{ fd, events });
            if (events.is_readable()) {
                var buffer: [1024]u8 = undefined;
                const size = try std.os.read(fd, buffer[0..]);
                if (size == 0) {
                    const removed = registry.deregister(fd);
                    std.os.close(fd);
                    std.debug.print("closed client fd={d}, removed={any} \n", .{ fd, removed });
                } else {
                    const written = try std.os.write(fd, buffer[0..size]);
                    _ = written;
                    //if (written < size) ?
                }
            }
        },
    }
    return 0;
}
