const std = @import("std");
const assert = std.debug.assert;
const micronet = @import("micronet");

const SocketType = enum { Server, Client };
const PollRegistry = micronet.PollRegistry(16);
const IoHandler = PollRegistry.IoHandler;
var echo_handler = EchoHandler{};

pub fn main() !void {
    var args_iter = std.process.args();

    const exe_name = args_iter.next() orelse return error.MissingArgument;
    _ = exe_name;
    const listen_ip = args_iter.next() orelse return error.MissingArgument;
    const port_name = args_iter.next() orelse return error.MissingArgument;
    const port_number = try std.fmt.parseInt(u16, port_name, 10);

    const addr = try std.net.Ip4Address.parse(listen_ip, port_number);
    const server_sock = try micronet.create_tcp_sock(addr);
    defer std.os.close(server_sock.fd);
    var registry = try PollRegistry.init();

    const callback = IoHandler.fromFunc(&server_accept);
    try registry.register(server_sock.fd, micronet.PollEvent.READ, callback);
    const timeout_millis = 100;
    while (true) {
        _ = try registry.poll(timeout_millis);
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
        const io_handler = echo_handler.io_handler();
        try pollReg.register(client_sock.fd, micronet.PollEvent.READ, io_handler);
    } else |err| {
        std.debug.print("accept error  {} \n", .{err});
    }

    return 1;
}

/// Io Handler which can have state ful ctx
/// need to have method to return IoHandler (compile time interface/static dispatch)
const EchoHandler = struct {
    pending_size: usize = 0,
    pending: [4096]u8 = undefined,

    fn add_pending(self: *EchoHandler, buff: []const u8) !void {
        assert(self.pending_size + buff.len < self.pending.len);
        const offset = self.pending_size;

        for (0.., buff) |i, byte| {
            self.pending[offset + i] = byte;
        }
        self.pending_size += buff.len;
    }

    fn write_pending(self: *EchoHandler, fd: std.os.fd_t) !void {
        const size = self.pending_size;
        const written = try std.os.write(fd, self.pending[0..size]);
        const pending = size - written;
        if (pending > 0) {
            std.mem.copyForwards(u8, self.pending[0..pending], self.pending[written..size]);
        }
        self.pending_size = pending;
    }

    fn echo_back(self: *EchoHandler, pollReg: *PollRegistry, events: micronet.PollEvent, fd: std.os.fd_t, buffer: []const u8) !usize {
        const size = buffer.len;
        if (std.os.write(fd, buffer)) |written| {
            if (written < size) {
                try pollReg.register(fd, micronet.PollEvent.WRITE, self.io_handler());
                try self.add_pending(buffer[written..size]);
                return written;
            }
        } else |err| {
            switch (err) {
                error.WouldBlock => {
                    try pollReg.register(fd, micronet.PollEvent.WRITE, self.io_handler());
                    try self.add_pending(buffer[0..size]);
                },
                else => {
                    std.debug.print("write error {}, event={} closing connection {d}\n", .{ err, events, fd });
                    close(pollReg, fd);
                },
            }
        }
        return 0;
    }
    pub fn do_echo(self: *EchoHandler, pollReg: *PollRegistry, fd: std.os.fd_t, events: micronet.PollEvent) anyerror!usize {
        var buffer: [4096]u8 = undefined;
        if (events.is_writable()) {
            try self.write_pending(fd);
            if (self.pending_size == 0) {
                //ready to read again
                try pollReg.register(fd, micronet.PollEvent.READ, self.io_handler());
            }
        }
        if (events.is_readable()) {
            if (std.os.read(fd, buffer[0..])) |size| {
                if (size == 0) {
                    close(pollReg, fd);
                } else {
                    _ = try self.echo_back(pollReg, events, fd, buffer[0..size]);
                }
            } else |err| {
                std.debug.print("read error {}, events={} \n", .{ err, events });
                close(pollReg, fd);
            }
        }
        return 0;
    }

    fn handle_io(ptr: *anyopaque, pollReg: *PollRegistry, fd: std.os.fd_t, events: micronet.PollEvent) !usize {
        const self: *EchoHandler = @ptrCast(@alignCast(ptr));
        if (do_echo(self, pollReg, fd, events)) |size| {
            return size;
        } else |err| {
            std.debug.print("error {} closing fd={d}", .{ err, fd });
            close(pollReg, fd);
            return 0;
        }
    }

    pub fn io_handler(self: *EchoHandler) IoHandler {
        return .{ .ptr = self, .callback = .{ .method = handle_io } };
    }
};
