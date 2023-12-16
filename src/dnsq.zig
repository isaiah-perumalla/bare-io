const std = @import("std");

const testing = std.testing;

pub const Opcode = enum(u4) {
    query = 0,
    inverse_query = 1,
    status_request = 2,
    _,
};

pub const ResponseCode = enum(u4) {
    no_error = 0,
    /// The name server was unable to interpret the query.
    format_error = 1,
    /// The name server was unable to process this query due to a
    /// problem with the name server.
    server_failure = 2,
    /// Meaningful only for responses from an authoritative name
    /// server, this code signifies that the domain name
    /// referenced in the query does not exist.
    name_error = 3,
    ///  The name server does not support the requested kind of
    ///  query.
    not_implemented = 4,
    /// The name server refuses to perform the specified operation
    /// for policy reasons.
    refused = 5,
    _,
};

pub const RRType = enum(u16) { A = 1, MX = 15, TXT = 16, SRV = 33 };

//only internet class supported
pub const Class = enum(u16) {
    /// The Internet
    IN = 1,
};

pub const Header = packed struct(u96) {
    id: u16,

    // Flags section. Fields are ordered this way because zig has
    // little endian bit order for bit fields.

    // Byte one

    /// Directs the name server to pursue the query recursively.
    /// Recursive query support is optional.
    recursion: bool,
    /// If the message was truncated
    truncation: bool,
    /// The responding name server is an authority for the domain name
    /// in question section.
    authoritative_answer: bool,
    /// Kind of query in this message. This value is set by the
    /// originator of a query and copied into the response.
    opcode: Opcode,
    /// Specifies whether this message is a query (false), or a
    /// response (true).
    response: bool,

    // Byte two

    /// Set as part of responses.
    response_code: ResponseCode,
    /// Reserved. Must be zero
    z: u3 = 0,
    /// Set or cleared in a response, and denotes whether recursive
    /// query support is available in the name server.
    recursion_available: bool,

    // End of flag section.

    /// The number of entries in the question section.
    question_count: u16,
    /// The number of resource records in the answer section.
    answer_count: u16,
    /// The number of name server resource records in the authority
    /// records section.
    name_server_count: u16,
    /// The number of resource records in the additional records
    /// section.
    additional_record_count: u16,
};

/// A domain name represented as a sequence of labels, where each
/// label consists of a length octet followed by that number of
/// octets. The domain name terminates with the zero length octet for
/// the null label of the root. Note that this field may be an odd
/// number of octets; no padding is used.
pub fn encode_domain(name: []const u8, out: []u8) !usize {
    _ = out;
    _ = name;
}

test "encode domain name" {
    try testing.expectEqualSlices(u8, "dns-todo", "dns-todo");
}
