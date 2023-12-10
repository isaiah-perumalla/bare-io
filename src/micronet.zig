const std = @import("std");

const testing = std.testing;

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
};

pub fn PollRegistry(comptime T: type, comptime max_size: u10) type {
    return struct {
        const Self = @This();

        const TagList = std.BoundedArray(T, max_size);
        const PollFdList = std.BoundedArray(std.os.pollfd, max_size);
        pollFds: PollFdList,
        tags: TagList,

        pub fn init(size: usize) !Self {
            return Self{ .pollFds = try PollFdList.init(size), .tags = try TagList.init(size) };
        }

        pub fn register(self: *Self, tag: T, fd: std.os.fd_t, interest: PollEvent) !void {
            std.debug.assert(self.pollFds.len == self.tags.len);
            const events: i16 = @bitCast(interest);
            var pollFds = self.pollFds.slice();
            for (0.., pollFds) |index, *pollFdPtr| {
                if (pollFdPtr.fd == fd) {
                    pollFdPtr.events = events;
                    pollFdPtr.revents = 0;
                    self.tags.set(index, tag);
                    return;
                }
            }

            const pollFd = std.os.pollfd{ .fd = fd, .events = events, .revents = 0 };
            try self.pollFds.append(pollFd);
            try self.tags.append(tag);
        }
    };
}

pub const Socket = struct {
    fd: std.os.socket_t,
    addr: std.net.Ip4Address,

    pub fn accept(self: Socket) !Socket {
        var client_addr: std.os.sockaddr.in = undefined; //holder for client address
        var addr_size: std.os.socklen_t = @sizeOf(std.os.sockaddr.in); //holder for size of address when filled
        const addr_ptr: *std.os.sockaddr = @ptrCast(&client_addr);

        const fd = try std.os.accept(self.fd, addr_ptr, &addr_size, std.os.O.NONBLOCK);
        return Socket{ .fd = fd, .addr = std.net.Ip4Address{ .sa = client_addr } };
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

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try testing.expect(add(3, 7) == 10);
}
