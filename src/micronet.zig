const std = @import("std");

const testing = std.testing;

const CallbackType = enum { method, function };

pub const PollEvent = packed struct(i16) {
    IN: bool = false,
    PRI: bool = false,
    OUT: bool = false,
    ERR: bool = false,
    HUP: bool = false,
    NVAL: bool = false,
    RDNORM: bool = false,
    RDBAND: bool = false,
    _padding: u8 = 0,

    pub fn as_flags(self: PollEvent) i16 {
        return @bitCast(self);
    }

    pub const READ: PollEvent = .{ .IN = true, .PRI = true };
    pub const WRITE: PollEvent = .{ .OUT = true };

    pub fn is_readable(self: PollEvent) bool {
        return self.IN or self.PRI;
    }
};

pub fn PollRegistry(comptime max_size: u10) type {
    return struct {
        const Result = struct { fd: std.os.fd_t, events: PollEvent, io_handler: IoHandler };
        const FuncCallback = *const fn (pollReg: *Self, fd: std.os.fd_t, events: PollEvent) anyerror!usize;
        const MethodCallback = *const fn (ctx: *anyopaque, *Self, fd: std.os.fd_t, events: PollEvent) anyerror!usize;
        const Callback = union(CallbackType) { method: MethodCallback, function: FuncCallback };
        const Self = @This();

        pub const IoHandler = struct {
            ptr: ?*anyopaque,
            callback: Callback,

            pub fn fromFunc(cb: FuncCallback) IoHandler {
                return .{ .ptr = null, .callback = .{ .function = cb } };
            }

            pub fn handle_event(self: IoHandler, pollReg: *Self, fd: std.os.fd_t, events: PollEvent) anyerror!usize {
                switch (self.callback) {
                    .function => |func| return func(pollReg, fd, events),
                    .method => |method| if (self.ptr != null) {
                        const ptr = self.ptr.?;
                        return method(ptr, pollReg, fd, events);
                    } else {
                        unreachable;
                    },
                }
            }
        };

        const IoHandlers = std.BoundedArray(IoHandler, max_size);
        const PollFdList = std.BoundedArray(std.os.pollfd, max_size);

        pollFds: PollFdList,
        ioHandles: IoHandlers,

        pub fn init() !Self {
            return Self{ .pollFds = try PollFdList.init(0), .ioHandles = try IoHandlers.init(0) };
        }

        pub fn poll_results(self: *Self, timeout_millis: i32, results: []Result) !usize {
            const size = try std.os.poll(self.pollFds.slice(), timeout_millis);
            if (size == 0) return 0;
            var processed: usize = 0;
            var pollFds = self.pollFds.slice();
            for (0.., pollFds) |idx, *ptr| {
                if (ptr.revents != 0) {
                    const events = ptr.revents;
                    results[processed] = Result{ .events = @bitCast(events), .fd = ptr.fd, .io_handler = self.ioHandles.get(idx) };
                    processed += 1;
                }
                ptr.revents = 0;
                if (processed == size) break;
            }
            return size;
        }

        pub fn poll(self: *Self, timeout_millis: i32) !usize {
            var results: [max_size]Result = undefined;
            const size = try self.poll_results(timeout_millis, results[0..]);

            for (results[0..size]) |res| {
                _ = try res.io_handler.handle_event(self, res.fd, res.events);
            }
            return size;
        }

        pub fn register(self: *Self, fd: std.os.fd_t, interest: PollEvent, ioHandler: IoHandler) !void {
            std.debug.assert(self.pollFds.len == self.ioHandles.len);
            const events: i16 = @bitCast(interest);
            var pollFds = self.pollFds.slice();
            for (0.., pollFds) |index, *pollFdPtr| {
                if (pollFdPtr.fd == fd) {
                    pollFdPtr.events = events;
                    pollFdPtr.revents = 0;
                    self.ioHandles.set(index, ioHandler);
                    return;
                }
            }

            const pollFd = std.os.pollfd{ .fd = fd, .events = events, .revents = 0 };
            try self.pollFds.append(pollFd);
            try self.ioHandles.append(ioHandler);
        }

        pub fn deregister(self: *Self, fd: std.os.fd_t) bool {
            var pollFds = self.pollFds.slice();
            for (0.., pollFds) |index, *pollFdPtr| {
                if (pollFdPtr.fd == fd) {
                    _ = self.ioHandles.swapRemove(index);
                    _ = self.pollFds.swapRemove(index);
                    return true;
                }
            }
            return false;
        }
    };
}

pub const Socket = struct {
    fd: std.os.socket_t,
    addr: std.net.Ip4Address,

    pub fn accept(fd: std.os.fd_t) !Socket {
        var client_addr: std.os.sockaddr.in = undefined; //holder for client address
        var addr_size: std.os.socklen_t = @sizeOf(std.os.sockaddr.in); //holder for size of address when filled
        const addr_ptr: *std.os.sockaddr = @ptrCast(&client_addr);

        const client_fd = try std.os.accept(fd, addr_ptr, &addr_size, std.os.O.NONBLOCK);
        return Socket{ .fd = client_fd, .addr = std.net.Ip4Address{ .sa = client_addr } };
    }
};
pub fn create_tcp_sock(addr: std.net.Ip4Address) !Socket {

    // const tcp = std.os.linux.socket(domain: u32, socket_type: u32, protocol: u32)
    const sock_type = std.os.SOCK.STREAM | std.os.SOCK.NONBLOCK | std.os.SOCK.CLOEXEC; // non blocking by default
    const sock = try std.os.socket(std.os.AF.INET, sock_type, 0);

    try std.os.bind(sock, @ptrCast(&addr.sa), addr.getOsSockLen());
    try std.os.listen(sock, 64);
    return Socket{ .addr = addr, .fd = sock };
}

test "test poll registry" {
    const Registry = PollRegistry(u8, comptime 4);
    var registry = try Registry.init();
    try registry.register('C', 1, PollEvent.READ);
}
