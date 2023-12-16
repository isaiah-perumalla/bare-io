const std = @import("std");
const micronet = @import("micronet");

const SocketType = enum { Server, Client };
const PollRegistry = micronet.PollRegistry(16);
const IoHandler = PollRegistry.IoHandler;
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
    

    const callback = IoHandler.fromFunc(&server_accept);
    try registry.register(server_sock.fd, micronet.PollEvent.READ, callback);
    const timeout_millis = 100;
    while (true) {
        const events = try registry.poll(timeout_millis);
        if (events != 0) {
            std.debug.print("events processed {d}\n", .{events});
        }
    }
}

fn close(registry: *PollRegistry, fd: std.os.fd_t) void {
    const removed = registry.deregister(fd);
    std.os.close(fd);
    std.debug.print("closed client fd={d}, removed={any} \n", .{ fd, removed });
}

fn server_accept(pollReg: *PollRegistry, fd: std.os.fd_t, events: micronet.PollEvent) anyerror!usize {
    _ = events;
    if (micronet.Socket.accept(fd)) |client_sock| {
        std.debug.print("client connected {}\n", .{client_sock.addr});
        const callback = IoHandler.fromFunc(&do_echo);
        try pollReg.register(client_sock.fd, micronet.PollEvent.READ, callback);
    } else |err| {
        std.debug.print("accept error  {} \n", .{err});
    }

    return 1;
}

fn do_echo(pollReg: *PollRegistry, fd: std.os.fd_t, events: micronet.PollEvent) anyerror!usize {
    _ = events;
    var buffer: [1024]u8 = undefined;

    if (std.os.read(fd, buffer[0..])) |size| {
        if (size == 0) {
            close(pollReg, fd);
        } else if (std.os.write(fd, buffer[0..size])) |written| {
            if (written < size) {
                std.debug.print("write not competed fd={d}, size={d}, written={d}\n", .{ fd, size, written });
            }
            return written;
        } else |err| {
            std.debug.print("write error {} closing connection {d}\n", .{ err, fd });
            close(pollReg, fd);
        }
    } else |err| {
        std.debug.print("read error {} \n", .{err});
        close(pollReg, fd);
    } //if (written < size) ?

    return 0;
}
