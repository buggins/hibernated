/**
 * A native D driver for the MySQL database system. Source file mysql.d.
 *
 * This module attempts to provide composite objects and methods that will allow a wide range of common database
 * operations, but be relatively easy to use. The design is a first attempt to illustrate the structure of a set of modules
 * to cover popular database systems and ODBC.
 *
 * It has no dependecies on GPL header files or libraries, instead communicating directly with the server via the
 * published client/server protocol.
 *
 * $(LINK http://dev.mysql.com/doc/internals/en/client-server-protocol.html)$(BR)
 *
 * This version is not by any means comprehensive, and there is still a good deal of work to do. As a general design
 * position it avoids providing wrappers for operations that can be accomplished by simple SQL sommands, unless
 * the command produces a result set. There are some instances of the latter category to provide simple meta-data
 * for the database,
 *
 * Its primary objects are:
 * $(UL
 *    $(LI Connection: $(UL $(LI Connection to the server, and querying and setting of server parameters.)))
 *    $(LI Command:  Handling of SQL requests/queries/commands, with principal methods:
 *       $(UL $(LI execSQL() - plain old SQL query.)
 *            $(LI execTuple() - get a set of values from a select or similar query into a matching tuple of D variables.)
 *            $(LI execPrepared() - execute a prepared statement.)
 *            $(LI execResult() - execute a raw SQL statement and get a complete result set.)
 *            $(LI execSequence() - execute a raw SQL statement and handle the rows one at a time.)
 *            $(LI execPreparedResult() - execute a prepared statement and get a complete result set.)
 *            $(LI execPreparedSequence() - execute a prepared statement and handle the rows one at a time.)
 *            $(LI execFunction() - execute a stored function with D variables as input and output.)
 *            $(LI execProcedure() - execute a stored procedure with D variables as input.)
 *        )
 *    )
 *    $(LI ResultSet: $(UL $(LI A random access range of rows, where a Row is basically an array of variant.)))
 *    $(LI ResultSequence: $(UL $(LIAn input range of similar rows.)))
 * )
 *
 * There are numerous examples of usage in the unittest sections.
 *
 * The file mysqld.sql, included with the module source code, can be used to generate the tables required by the unit tests.
 *
 * This requires a MySQL server v4.1.1 or later. Older versions of MySQL server
 * are obsolete, use known-insecure authentication, and are not supported by this module.
 *
 * There is an outstanding issue with Connections. Normally MySQL clients sonnect to a server on the same machine
 * via a Unix socket on *nix systems, and through a named pipe on Windows. Neither of these conventions is
 * currently supported. TCP must be used for all connections.
 *
 * Since there is currently no SHA1 support on Phobos, a simple translation of the NIST example C code for SHA1
 * is also included with this module.
 *
 * Copyright: Copyright 2011
 * License:   $(LINK www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Author:   Steve Teale
 */
module mysql.connection;

import mysql.sha1;

import vibe.core.net;
import vibe.utils.string;

import std.algorithm;
import std.conv;
import std.datetime;
import std.exception;
import std.range;
import std.stdio;
import std.string;
import std.traits;
import std.variant;

/**
 * An exception type to distinguish exceptions thrown by this module.
 */
class MySQLException: Exception
{
    this(string msg, string file, size_t line) { super(msg, file, line); }
}
alias MySQLException MYX;

/**
 * A simple struct to represent time difference.
 *
 * D's std.datetime does not have a type that is closely compatible with the MySQL
 * interpretation of a time difference, so we define a struct here to hold such
 * values.
 */
struct TimeDiff
{
    bool negative;
    int days;
    ubyte hours, minutes, seconds;
}

/**
 * Function to extract a time difference from a binary encoded row.
 *
 * Time/date structures are packed by the server into a byte sub-packet
 * with a leading length byte, and a minimal number of bytes to embody the data.
 *
 * Params: a = slice of a protocol packet beginning at the length byte for a chunk of time data
 *
 * Returns: A populated or default initialized TimeDiff struct.
 */
TimeDiff toTimeDiff(ubyte[] a)
{
    enforceEx!MYX(a.length, "Supplied byte array is zero length");
    TimeDiff td;
    uint l = a[0];
    enforceEx!MYX(l == 0 || l == 5 || l == 8 || l == 12, "Bad Time length in binary row.");
    if (l >= 5)
    {
        td.negative = (a[1]  != 0);
        td.days     = (a[5] << 24) + (a[4] << 16) + (a[3] << 8) + a[2];
    }
    if (l >= 8)
    {
        td.hours    = a[6];
        td.minutes  = a[7];
        td.seconds  = a[8];
    }
    // Note that the fractional seconds part is not stored by MySQL
    return td;
}

/**
 * Function to extract a time difference from a text encoded column value.
 *
 * Text representations of a time difference are like -750:12:02 - 750 hours
 * 12 minutes and two seconds ago.
 *
 * Params: s = A string representation of the time difference.
 * Returns: A populated or default initialized TimeDiff struct.
 */
TimeDiff toTimeDiff(string s)
{
    TimeDiff td;
    int t = parse!int(s);
    if (t < 0)
    {
        td.negative = true;
        t = -t;
    }
    td.hours    = t%24;
    td.days     = t/24;
    munch(s, ":");
    td.minutes  = parse!ubyte(s);
    munch(s, ":");
    td.seconds  = parse!ubyte(s);
    return td;
}

/**
 * Function to extract a TimeOfDay from a binary encoded row.
 *
 * Time/date structures are packed by the server into a byte sub-packet
 * with a leading length byte, and a minimal number of bytes to embody the data.
 *
 * Params: a = slice of a protocol packet beginning at the length byte for a chunk of time data
 * Returns: A populated or default initialized std.datetime.TimeOfDay struct.
 */
TimeOfDay toTimeOfDay(ubyte[] a)
{
    enforceEx!MYX(a.length, "Supplied byte array is zero length");
    uint l = a[0];
    enforceEx!MYX(l == 0 || l == 5 || l == 8 || l == 12, "Bad Time length in binary row.");
    enforceEx!MYX(l >= 8, "Time column value is not in a time-of-day format");

    TimeOfDay tod;
    tod.hour    = a[6];
    tod.minute  = a[7];
    tod.second  = a[8];
    return tod;
}

/**
 * Function to extract a TimeOfDay from a text encoded column value.
 *
 * Text representations of a time of day are as in 14:22:02
 *
 * Params: s = A string representation of the time.
 * Returns: A populated or default initialized std.datetime.TimeOfDay struct.
 */
TimeOfDay toTimeOfDay(string s)
{
    TimeOfDay tod;
    tod.hour = parse!int(s);
    enforceEx!MYX(tod.hour <= 24 && tod.hour >= 0, "Time column value is in time difference form");
    munch(s, ":");
    tod.minute = parse!ubyte(s);
    munch(s, ":");
    tod.second = parse!ubyte(s);
    return tod;
}

/**
 * Function to pack a TimeOfDay into a binary encoding for transmission to the server.
 *
 * Time/date structures are packed into a string of bytes with a leading length byte,
 * and a minimal number of bytes to embody the data.
 *
 * Params: tod = TimeOfDay struct.
 * Returns: Packed ubyte[].
 */
ubyte[] pack(TimeOfDay tod)
{
    ubyte[] rv;
    if (tod == TimeOfDay.init)
    {
        rv.length = 1;
        rv[0] = 0;
    }
    else
    {
        rv.length = 9;
        rv[0] = 8;
        rv[6] = tod.hour;
        rv[7] = tod.minute;
        rv[8] = tod.second;
    }
    return rv;
}

/**
 * Function to extract a Date from a binary encoded row.
 *
 * Time/date structures are packed by the server into a byte sub-packet
 * with a leading length byte, and a minimal number of bytes to embody the data.
 *
 * Params: a = slice of a protocol packet beginning at the length byte for a chunk of Date data
 * Returns: A populated or default initialized std.datetime.Date struct.
 */
Date toDate(ubyte[] a)
{
    enforceEx!MYX(a.length, "Supplied byte array is zero length");
    if (a[0] == 0)
        return Date(0,0,0);

    enforceEx!MYX(a[0] >= 4, "Binary date representation is too short");
    int year    = (a[2]  << 8) + a[1];
    int month   = cast(int) a[3];
    int day     = cast(int) a[4];
    return Date(year, month, day);
}

/**
 * Function to extract a Date from a text encoded column value.
 *
 * Text representations of a Date are as in 2011-11-11
 *
 * Params: a = A string representation of the time difference.
 * Returns: A populated or default initialized std.datetime.Date struct.
 */
Date toDate(string s)
{
    int year = parse!(ushort)(s);
    munch(s, "-");
    int month = parse!(ubyte)(s);
    munch(s, "-");
    int day = parse!(ubyte)(s);
    return Date(year, month, day);
}

/**
 * Function to pack a Date into a binary encoding for transmission to the server.
 *
 * Time/date structures are packed into a string of bytes with a leading length byte,
 * and a minimal number of bytes to embody the data.
 *
 * Params: dt = std.datetime.Date struct.
 * Returns: Packed ubyte[].
 */
ubyte[] pack(Date dt)
{
    ubyte[] rv;
    if (dt.year < 0)
    {
        rv.length = 1;
        rv[0] = 0;
    }
    else
    {
        rv.length = 4;
        rv[0] = 4;
        rv[1] = cast(ubyte) ( dt.year       & 0xff);
        rv[2] = cast(ubyte) ((dt.year >> 8) & 0xff);
        rv[3] = cast(ubyte)   dt.month;
        rv[4] = cast(ubyte)   dt.day;
    }
    return rv;
}

/**
 * Function to extract a DateTime from a binary encoded row.
 *
 * Time/date structures are packed by the server into a byte sub-packet
 * with a leading length byte, and a minimal number of bytes to embody the data.
 *
 * Params: a = slice of a protocol packet beginning at the length byte for a chunk of
 *                       DateTime data
 * Returns: A populated or default initialized std.datetime.DateTime struct.
 */
DateTime toDateTime(ubyte[] a)
{
    enforceEx!MYX(a.length, "Supplied byte array is zero length");
    if (a[0] == 0)
        return DateTime();

    enforceEx!MYX(a[0] >= 4, "Supplied ubyte[] is not long enough");
    int year    = (a[2] << 8) + a[1];
    int month   =  a[3];
    int day     =  a[4];
    DateTime dt;
    if (a[0] == 4)
    {
        dt = DateTime(year, month, day);
    }
    else
    {
        enforceEx!MYX(a[0] >= 7, "Supplied ubyte[] is not long enough");
        int hour    = a[5];
        int minute  = a[6];
        int second  = a[7];
        dt = DateTime(year, month, day, hour, minute, second);
    }
    return dt;
}

/**
 * Function to extract a DateTime from a text encoded column value.
 *
 * Text representations of a DateTime are as in 2011-11-11 12:20:02
 *
 * Params: a = A string representation of the time difference.
 * Returns: A populated or default initialized std.datetime.DateTime struct.
 */
DateTime toDateTime(string s)
{
    int year = parse!(ushort)(s);
    munch(s, "-");
    int month = parse!(ubyte)(s);
    munch(s, "-");
    int day = parse!(ubyte)(s);
    munch(s, " ");
    int hour = parse!(ubyte)(s);
    munch(s, ":");
    int minute = parse!(ubyte)(s);
    munch(s, ":");
    int second = parse!(ubyte)(s);
    return DateTime(year, month, day, hour, minute, second);
}

/**
 * Function to extract a DateTime from a ulong.
 *
 * This is used to support the TimeStamp  struct.
 *
 * Params: x = A ulong e.g. 20111111122002UL.
 * Returns: A populated std.datetime.DateTime struct.
 */
DateTime toDateTime(ulong x)
{
    int second = cast(int) x%100;
    x /= 100;
    int minute = cast(int) x%100;
    x /= 100;
    int hour   = cast(int) x%100;
    x /= 100;
    int day    = cast(int) x%100;
    x /= 100;
    int month  = cast(int) x%100;
    x /= 100;
    int year   = cast(int) x%10000;
    // 2038-01-19 03:14:07
    enforceEx!MYX(year >= 1970 &&  year < 2039, "Date/time out of range for 2 bit timestamp");
    enforceEx!MYX(year == 2038 && (month > 1 || day > 19 || hour > 3 || minute > 14 || second > 7),
            "Date/time out of range for 2 bit timestamp");
    return DateTime(year, month, day, hour, minute, second);
}

/**
 * Function to pack a DateTime into a binary encoding for transmission to the server.
 *
 * Time/date structures are packed into a string of bytes with a leading length byte,
 * and a minimal number of bytes to embody the data.
 *
 * Params: dt = std.datetime.DateTime struct.
 * Returns: Packed ubyte[].
 */
ubyte[] pack(DateTime dt)
{
    uint len = 1;
    if (dt.year || dt.month || dt.day) len = 5;
    if (dt.hour || dt.minute|| dt.second) len = 8;
    ubyte[] rv;
    rv.length = len;
    rv[0] =  cast(ubyte)(rv.length - 1); // num bytes
    if(len >= 5)
    {
        rv[1] = cast(ubyte) ( dt.year       & 0xff);
        rv[2] = cast(ubyte) ((dt.year >> 8) & 0xff);
        rv[3] = cast(ubyte)   dt.month;
        rv[4] = cast(ubyte)   dt.day;
    }
    if(len == 8)
    {
        rv[5] = cast(ubyte) dt.hour;
        rv[6] = cast(ubyte) dt.minute;
        rv[7] = cast(ubyte) dt.second;
    }
    return rv;
}

/**
 * A D struct to stand for a TIMESTAMP
 *
 * It is assumed that insertion of TIMESTAMP values will not be common, since in general,
 * such columns are used for recording the time of a row insertion, and are filled in
 * automatically by the server. If you want to force a timestamp value in a prepared insert,
 * set it into a timestamp struct as an unsigned long in the format YYYYMMDDHHMMSS
 * and use that for the approriate parameter. When TIMESTAMPs are retrieved as part of
 * a result set it will be as DateTime structs.
 */
struct Timestamp
{
    ulong rep;
}

/**
 * Server capability flags.
 *
 * During the connection handshake process, the server sends a uint of flags describing its
 * capabilities
 *
 * See_Also: http://dev.mysql.com/doc/internals/en/connection-phase.html#capability-flags
 */
enum SvrCapFlags: uint
{
    OLD_LONG_PASSWORD   =      1, /// Long old-style passwords (Not 4.1+ passwords)
    FOUND_NOT_AFFECTED  =      2, /// Report rows found rather than rows affected
    ALL_COLUMN_FLAGS    =      4, /// Send all column flags
    WITH_DB             =      8, /// Can take database as part of login
    NO_SCHEMA           =     16, /// Can disallow database name as part of column name database.table.column
    CAN_COMPRESS        =     32, /// Can compress packets
    ODBC                =     64, /// Can handle ODBC
    LOCAL_FILES         =    128, /// Can use LOAD DATA LOCAL
    IGNORE_SPACE        =    256, /// Can ignore spaces before '('
    PROTOCOL41          =    512, /// Can use 4.1+ protocol
    INTERACTIVE         =   1024, /// Interactive client?
    SSL                 =   2048, /// Can switch to SSL after handshake
    IGNORE_SIGPIPE      =   4096, /// Ignore sigpipes?
    TRANSACTIONS        =   8192, /// Transaction support
    RESERVED            =  16384, //  Old flag for 4.1 protocol
    SECURE_CONNECTION   =  32768, /// 4.1+ authentication
    MULTI_STATEMENTS    =  65536, /// Multiple statement support
    MULTI_RESULTS       = 131072  /// Multiple result set support
}
// 000000001111011111111111
immutable SvrCapFlags defaultClientFlags =
        SvrCapFlags.OLD_LONG_PASSWORD | SvrCapFlags.ALL_COLUMN_FLAGS |
        SvrCapFlags.WITH_DB | SvrCapFlags.PROTOCOL41 |
        SvrCapFlags.SECURE_CONNECTION;// | SvrCapFlags.MULTI_STATEMENTS |
        //SvrCapFlags.MULTI_RESULTS;

/**
 * Column type codes
 */
enum SQLType : short
{
    INFER_FROM_D_TYPE = -1,
    DECIMAL      = 0x00,
    TINY         = 0x01,
    SHORT        = 0x02,
    INT          = 0x03,
    FLOAT        = 0x04,
    DOUBLE       = 0x05,
    NULL         = 0x06,
    TIMESTAMP    = 0x07,
    LONGLONG     = 0x08,
    INT24        = 0x09,
    DATE         = 0x0a,
    TIME         = 0x0b,
    DATETIME     = 0x0c,
    YEAR         = 0x0d,
    NEWDATE      = 0x0e,
    VARCHAR      = 0x0f, // new in MySQL 5.0
    BIT          = 0x10, // new in MySQL 5.0
    NEWDECIMAL   = 0xf6, // new in MYSQL 5.0
    ENUM         = 0xf7,
    SET          = 0xf8,
    TINYBLOB     = 0xf9,
    MEDIUMBLOB   = 0xfa,
    LONGBLOB     = 0xfb,
    BLOB         = 0xfc,
    VARSTRING    = 0xfd,
    STRING       = 0xfe,
    GEOMETRY     = 0xff
}

/**
 * Server refresh flags
 */
enum RefreshFlags : ubyte
{
    GRANT    =   1,
    LOG      =   2,
    TABLES   =   4,
    HOSTS    =   8,
    STATUS   =  16,
    THREADS  =  32,
    SLAVE    =  64,
    MASTER   = 128
}

/**
 * Type of Command Packet (COM_XXX)
 * See_Also: http://forge.mysql.com/wiki/MySQL_Internals_ClientServer_Protocol#Command_Packet_.28Overview.29
 * */
enum CommandType : ubyte
{
    SLEEP               = 0x00,
    QUIT                = 0x01,
    INIT_DB             = 0x02,
    QUERY               = 0x03,
    FIELD_LIST          = 0x04,
    CREATE_DB           = 0x05,
    DROP_DB             = 0x06,
    REFRESH             = 0x07,
    SHUTDOWN            = 0x08,
    STATISTICS          = 0x09,
    PROCESS_INFO        = 0x0a,
    CONNECT             = 0x0b,
    PROCESS_KILL        = 0x0c,
    DEBUG               = 0x0d,
    PING                = 0x0e,
    TIME                = 0x0f,
    DELAYED_INSERT      = 0x10,
    CHANGE_USER         = 0x11,
    BINLOG_DUBP         = 0x12,
    TABLE_DUMP          = 0x13,
    CONNECT_OUT         = 0x14,
    REGISTER_SLAVE      = 0x15,
    STMT_PREPARE        = 0x16,
    STMT_EXECUTE        = 0x17,
    STMT_SEND_LONG_DATA = 0x18,
    STMT_CLOSE          = 0x19,
    STMT_RESET          = 0x1a,
    STMT_OPTION         = 0x1b,
    STMT_FETCH          = 0x1c,
}

T consume(T)(TcpConnection conn) {
    ubyte[T.sizeof] buffer;
    conn.read(buffer);
    ubyte[] rng = buffer;
    return consume!T(rng);
}

string consume(T:string, ubyte N=T.sizeof)(ref ubyte[] packet)
{
    return packet.consume!string(N);
}

string consume(T:string)(ref ubyte[] packet, size_t N)
in
{
    assert(packet.length >= N);
}
body
{
    return cast(string)packet.consume(N);
}

/// Returns N number of bytes from the packet and advances the array
ubyte[] consume()(ref ubyte[] packet, size_t N)
in
{
    assert(packet.length >= N);
}
body
{
    auto result = packet[0..N];
    packet = packet[N..$];
    return result;
}

T decode(T:ulong)(in ubyte[] packet, size_t n)
{
    switch(n)
    {
        case 8: return packet.decode!(T, 8)();
        case 4: return packet.decode!(T, 4)();
        case 3: return packet.decode!(T, 3)();
        case 2: return packet.decode!(T, 2)();
        case 1: return packet.decode!(T, 1)();
        default: assert(0);
    }
}

T consume(T)(ref ubyte[] packet, int n) if(isIntegral!T)
{
    switch(n)
    {
        case 8: return packet.consume!(T, 8)();
        case 4: return packet.consume!(T, 4)();
        case 3: return packet.consume!(T, 3)();
        case 2: return packet.consume!(T, 2)();
        case 1: return packet.consume!(T, 1)();
        default: assert(0);
    }
}

TimeOfDay consume(T:TimeOfDay, ubyte N=T.sizeof)(ref ubyte[] packet)
in
{
    static assert(N == T.sizeof);
}
body
{
    enforceEx!MYX(packet.length, "Supplied byte array is zero length");
    uint length = packet.front;
    enforceEx!MYX(length == 0 || length == 5 || length == 8 || length == 12, "Bad Time length in binary row.");
    enforceEx!MYX(length >= 8, "Time column value is not in a time-of-day format");

    packet.popFront(); // length
    auto bytes = packet.consume(length);

    // TODO: What are the fields in between!?! Blank Date?
    TimeOfDay tod;
    tod.hour    = bytes[5];
    tod.minute  = bytes[6];
    tod.second  = bytes[7];
    return tod;
}

Date consume(T:Date, ubyte N=T.sizeof)(ref ubyte[] packet)
in
{
    static assert(N == T.sizeof);
}
body
{
    auto numBytes = packet.front;
    if(!numBytes)
        return Date(0,0,0);

    enforceEx!MYX(numBytes >= 4, "Binary date representation is too short");
    auto year    = packet.consume!ushort();
    auto month   = packet.consume!ubyte();
    auto day     = packet.consume!ubyte();
    return Date(year, month, day);
}

DateTime consume(T:DateTime, ubyte N=T.sizeof)(ref ubyte[] packet)
in
{
    assert(packet.length);
    assert(N == T.sizeof);
}
body
{
    auto numBytes = packet.consume!ubyte();
    if(numBytes == 0)
        return DateTime();

    enforceEx!MYX(numBytes >= 4, "Supplied packet is not large enough to store DateTime");

    int year    = packet.consume!ushort();
    int month   = packet.consume!ubyte();
    int day     = packet.consume!ubyte();
    int hour    = 0;
    int minute  = 0;
    int second  = 0;
    if(numBytes > 4)
    {
        enforceEx!MYX(numBytes >= 7, "Supplied packet is not large enough to store a DateTime with TimeOfDay");
        hour    = packet.consume!ubyte();
        minute  = packet.consume!ubyte();
        second  = packet.consume!ubyte();
    }
    return DateTime(year, month, day, hour, minute, second);
}

@property bool hasEnoughBytes(T, ubyte N=T.sizeof)(in ubyte[] packet)
in
{
    static assert(T.sizeof >= N, T.stringof~" not large enough to store "~to!string(N)~" bytes");
}
body
{
    return packet.length >= N;
}

T decode(T, ubyte N=T.sizeof)(in ubyte[] packet) if(isIntegral!T)
in
{
    static assert(N == 1 || N == 2 || N == 3 || N == 4 || N == 8, "Cannot decode integral value. Invalid size: "~N.stringof);
    static assert(T.sizeof >= N, T.stringof~" not large enough to store "~to!string(N)~" bytes");
    assert(packet.hasEnoughBytes!(T,N), "packet not long enough to contain all bytes needed for "~T.stringof);
}
body
{
    T value = 0;
    static if(N == 8) // 64 bit
    {
        value |= cast(T)(packet[7]) << (8*7);
        value |= cast(T)(packet[6]) << (8*6);
        value |= cast(T)(packet[5]) << (8*5);
        value |= cast(T)(packet[4]) << (8*4);
    }
    static if(N >= 4) // 32 bit
    {
        value |= cast(T)(packet[3]) << (8*3);
    }
    static if(N >= 3) // 24 bit
    {
        value |= cast(T)(packet[2]) << (8*2);
    }
    static if(N >= 2) // 16 bit
    {
        value |= cast(T)(packet[1]) << (8*1);
    }
    static if(N >= 1) // 8 bit
    {
        value |= cast(T)(packet[0]) << (8*0);
    }
    return value;
}

bool consume(T:bool, ubyte N=T.sizeof)(ref ubyte[] packet)
{
    static assert(N == 1);
    return packet.consume!ubyte() == 1;
}

T consume(T, ubyte N=T.sizeof)(ref ubyte[] packet) if(isIntegral!T)
in
{
    static assert(N == 1 || N == 2 || N == 3 || N == 4 || N == 8, "Cannot consume integral value. Invalid size: "~N.stringof);
    static assert(T.sizeof >= N, T.stringof~" not large enough to store "~to!string(N)~" bytes");
    assert(packet.hasEnoughBytes!(T,N), "packet not long enough to contain all bytes needed for "~T.stringof);
}
body
{
    // The uncommented line triggers a template deduction error,
    // so we need to store a temporary first
    // could the problem be method chaining?
    //return packet.consume(N).decode!(T, N)();
    auto bytes = packet.consume(N);
    return bytes.decode!(T, N)();
}

T myto(T)(string value)
{
    static if(is(T == DateTime))
        return toDateTime(value);
    else static if(is(T == Date))
        return toDate(value);
    else static if(is(T == TimeOfDay))
        return toTimeOfDay(value);
    else
        return to!T(value);
}

T decode(T, ubyte N=T.sizeof)(in ubyte[] packet) if(isFloatingPoint!T)
in
{
    static assert((is(T == float) && N == float.sizeof)
            || is(T == double) && N == double.sizeof);
}
body
{
    T result = 0;
    (cast(ubyte*)result)[0..T.sizeof] = packet[0..T.sizeof];
    return result;
}

T consume(T, ubyte N=T.sizeof)(ref ubyte[] packet) if(isFloatingPoint!T)
in
{
    static assert((is(T == float) && N == float.sizeof)
            || is(T == double) && N == double.sizeof);
}
body
{
    return packet.consume(T.sizeof).decode!T();
}

struct SQLValue
{
    bool isNull;
    bool isIncomplete;
    Variant _value;

    // empty template as a template and non-template won't be added to the same overload set
    @property Variant value()()
    {
        enforceEx!MYX(!isNull, "SQL value is null");
        enforceEx!MYX(!isIncomplete, "SQL value not complete");
        return _value;
    }

    @property void value(T)(T value)
    {
        enforceEx!MYX(!isNull, "SQL value is null");
        enforceEx!MYX(!isIncomplete, "SQL value not complete");
        _value = value;
    }

    invariant()
    {
        isNull && assert(!isIncomplete);
        isIncomplete && assert(!isNull);
    }
}

SQLValue consumeBinaryValueIfComplete(T, int N=T.sizeof)(ref ubyte[] packet, bool unsigned)
{
    SQLValue result;
    result.isIncomplete = packet.length < N;
    // isNull should have been handled by the caller as the binary format uses a null bitmap,
    // and we don't have access to that information at this point
    assert(!result.isNull);
    if(!result.isIncomplete)
    {
        // only integral types is unsigned
        static if(isIntegral!T)
        {
            if(unsigned)
                result.value = packet.consume!(Unsigned!T)();
            else
                result.value = packet.consume!(Signed!T)();
        }
        else
        {
            assert(!unsigned);
            // TODO: DateTime values etc might be incomplete!
            result.value = packet.consume!(T, N)();
        }
    }
    return result;
}

SQLValue consumeNonBinaryValueIfComplete(T)(ref ubyte[] packet, bool unsigned)
{
    SQLValue result;
    auto lcb = packet.decode!LCB();
    result.isIncomplete = lcb.isIncomplete || packet.length < (lcb.value+lcb.totalBytes);
    result.isNull = lcb.isNull;
    if(!result.isIncomplete)
    {
        // The packet has all the data we need, so we'll remove the LCB
        // and convert the data
        packet.skip(lcb.totalBytes);
        assert(packet.length >= lcb.value);
        auto value = cast(string) packet.consume(cast(size_t)lcb.value);

        if(!result.isNull)
        {
            assert(!result.isIncomplete);
            assert(!result.isNull);
            static if(isIntegral!T)
            {
                if(unsigned)
                    result.value = to!(Unsigned!T)(value);
                else
                    result.value = to!(Signed!T)(value);
            }
            else
            {
                assert(!unsigned);
                static if(isArray!T)
                {
                    // to!() crashes when trying to convert empty strings
                    // to arrays, so we have this hack to just store any
                    // empty array in those cases
                    if(!value.length)
                        result.value = T.init;
                    else
                        result.value = cast(T)value.dup;

                }
                else
                {
                    // TODO: DateTime values etc might be incomplete!
                    result.value = myto!T(value);
                }
            }
        }
    }
    return result;
}

SQLValue consumeIfComplete(T, int N=T.sizeof)(ref ubyte[] packet, bool binary, bool unsigned)
{
    return binary
        ? packet.consumeBinaryValueIfComplete!(T, N)(unsigned)
        : packet.consumeNonBinaryValueIfComplete!T(unsigned);
}

SQLValue consumeIfComplete()(ref ubyte[] packet, SQLType sqlType, bool binary, bool unsigned)
{
    switch(sqlType)
    {
        default: assert(false, "Unsupported SQL type "~to!string(sqlType));
        case SQLType.NULL:
            SQLValue result;
            result.isIncomplete = false;
            result.isNull = true;
            return result;
        case SQLType.BIT:
            return packet.consumeIfComplete!bool(binary, unsigned);
        case SQLType.TINY:
            return packet.consumeIfComplete!byte(binary, unsigned);
        case SQLType.SHORT:
            return packet.consumeIfComplete!short(binary, unsigned);
        case SQLType.INT24:
            return packet.consumeIfComplete!(int, 3)(binary, unsigned);
        case SQLType.INT:
            return packet.consumeIfComplete!int(binary, unsigned);
        case SQLType.LONGLONG:
            return packet.consumeIfComplete!long(binary, unsigned);
        case SQLType.FLOAT:
            return packet.consumeIfComplete!float(binary, unsigned);
        case SQLType.DOUBLE:
            return packet.consumeIfComplete!double(binary, unsigned);
        case SQLType.TIMESTAMP:
            return packet.consumeIfComplete!DateTime(binary, unsigned);
        case SQLType.TIME:
            return packet.consumeIfComplete!TimeOfDay(binary, unsigned);
        case SQLType.YEAR:
            return packet.consumeIfComplete!ushort(binary, unsigned);
        case SQLType.DATE:
            return packet.consumeIfComplete!Date(binary, unsigned);
        case SQLType.DATETIME:
            return packet.consumeIfComplete!DateTime(binary, unsigned);
        case SQLType.VARCHAR:
        case SQLType.ENUM:
        case SQLType.SET:
        case SQLType.VARSTRING:
        case SQLType.STRING:
            return packet.consumeIfComplete!string(false, unsigned);
        case SQLType.TINYBLOB:
        case SQLType.MEDIUMBLOB:
        case SQLType.BLOB:
        case SQLType.LONGBLOB:
            auto lcb = packet.consumeIfComplete!LCB();
            assert(!lcb.isIncomplete);
            SQLValue result;
            result.isIncomplete = false;
            result.isNull = false;
            result.value = packet.consume(cast(size_t)lcb.value);
            return result;
    }
}

/**
 * Extract number of bytes used for this LCB
 *
 * Returns the number of bytes required to store this LCB
 *
 * See_Also: http://forge.mysql.com/wiki/MySQL_Internals_ClientServer_Protocol#Elements
 *
 * Returns: 0 if it's a null value, or number of bytes in other cases
 * */
byte getNumLCBBytes(ubyte lcbHeader)
{
    switch(lcbHeader)
    {
        case 251: return 0; // null
        case 0: .. case 250: return 1; // 8-bit
        case 252: return 2;  // 16-bit
        case 253: return 3;  // 24-bit
        case 254: return 8;  // 64-bit

        case 255:
        default:
            assert(0);
    }
    assert(0);
}

/** Parse Length Coded Binary
 *
 * See_Also: http://forge.mysql.com/wiki/MySQL_Internals_ClientServer_Protocol#Elements
 */
ulong parseLCB(ref ubyte* ubp, out bool nullFlag)
{
    nullFlag = false;
    ulong t;
    byte numLCBBytes = getNumLCBBytes(*ubp);
    switch (numLCBBytes)
    {
        case 0: // Null - only for Row Data Packet
            nullFlag = true;
            t = 0;
            break;
        case 8: // 64-bit
            t |= ubp[8];
            t <<= 8;
            t |= ubp[7];
            t <<= 8;
            t |= ubp[6];
            t <<= 8;
            t |= ubp[5];
            t <<= 8;
            t |= ubp[4];
            t <<= 8;
            ubp += 5;
            goto case;
        case 3: // 24-bit
            t |= ubp[3];
            t <<= 8;
            t |= ubp[2];
            t <<= 8;
            t |= ubp[1];
            ubp += 3;
            goto case;
        case 2: // 16-bit
            t |= ubp[2];
            t <<= 8;
            t |= ubp[1];
            ubp += 2;
            break;
        case 1: // 8-bit
            t = cast(ulong)*ubp;
            break;
        default:
            assert(0);
    }
    ubp++;
    return t;
}

/// ditto
ulong parseLCB(ref ubyte* ubp)
{
    bool isNull;
    return parseLCB(ubp, isNull);
}

/**
 * Length Coded Binary Value
 * */
struct LCB
{
    /// True if the LCB contains a null value
    bool isNull;

    /// True if the packet that created this LCB didn't have enough bytes
    /// to store a value of the size specified. More bytes have to be fetched from the server
    bool isIncomplete;

    // Number of bytes needed to store the value (Extracted from the LCB header. The header byte is not included)
    ubyte numBytes;

    // Number of bytes total used for this LCB
    @property ubyte totalBytes()
    {
        return cast(ubyte)(numBytes <= 1 ? 1 : numBytes+1);
    }

    /// The decoded value. This is always 0 if isNull or isIncomplete is set.
    ulong value;

    invariant()
    {
        if(isIncomplete)
        {
            assert(!isNull);
            assert(value == 0);
            assert(numBytes > 0);
        }
        else if(isNull)
        {
            assert(!isIncomplete);
            assert(value == 0);
            assert(numBytes == 0);
        }
        else
        {
            assert(!isNull);
            assert(!isIncomplete);
            assert(numBytes > 0);
        }
    }
}

/**
 * Decodes a Length Coded Binary from a packet
 *
 * See_Also: struct LCB
 *
 * Parameters:
 *  packet = A packet that starts with a LCB. The bytes is popped off
 *           iff the packet is complete. See LCB.
 *
 * Returns: A decoded LCB value
 * */
T consumeIfComplete(T:LCB)(ref ubyte[] packet)
in
{
    assert(packet.length >= 1, "packet has to include at least the LCB length byte");
}
body
{
    auto lcb = packet.decodeLCBHeader();
    if(lcb.isNull || lcb.isIncomplete)
        return lcb;

    if(lcb.numBytes > 1)
    {
        // We know it's complete, so we have to start consuming the LCB
        // Single byte values doesn't have a length
        packet.popFront(); // LCB length
    }

    assert(packet.length >= lcb.numBytes);

    lcb.value = packet.consume!ulong(lcb.numBytes);
    return lcb;
}

LCB decodeLCBHeader(in ubyte[] packet)
in
{
    assert(packet.length >= 1, "packet has to include at least the LCB length byte");
}
body
{
    LCB lcb;
    lcb.numBytes = getNumLCBBytes(packet.front);
    if(lcb.numBytes == 0)
    {
        lcb.isNull = true;
        return lcb;
    }

    assert(!lcb.isNull);
    lcb.isIncomplete = (lcb.numBytes > 1) && (packet.length-1 < lcb.numBytes); // -1 for LCB length as we haven't popped it off yet
    if(lcb.isIncomplete)
    {
        // Not enough bytes to store data. We don't remove any data, and expect
        // the caller to check isIncomplete and take action to fetch more data
        // and call this method at a later time
        return lcb;
    }

    assert(!lcb.isIncomplete);
    return lcb;
}

/**
 * Decodes a Length Coded Binary from a packet
 *
 * See_Also: struct LCB
 *
 * Parameters:
 *  packet = A packet that starts with a LCB. See LCB.
 *
 * Returns: A decoded LCB value
 * */
LCB decode(T:LCB)(in ubyte[] packet)
in
{
    assert(packet.length >= 1, "packet has to include at least the LCB length byte");
}
body
{
    auto lcb = packet.decodeLCBHeader();
    if(lcb.isNull || lcb.isIncomplete)
        return lcb;
    assert(packet.length >= lcb.totalBytes);
    lcb.value = packet.decode!ulong(lcb.numBytes);
    return lcb;
}

/** Length Coded String
 * */
struct LCS
{
    // dummy struct just to tell what value we are using
    // we don't need to store anything here as the result is always a string
}

/** Parse Length Coded String
 *
 * See_Also: http://forge.mysql.com/wiki/MySQL_Internals_ClientServer_Protocol#Elements
 * */
string consume(T:LCS)(ref ubyte[] packet)
in
{
    assert(packet.length >= 1, "LCS packet needs to store at least the LCB header");
}
body
{
    auto lcb = packet.consumeIfComplete!LCB();
    assert(!lcb.isIncomplete);
    if(lcb.isNull)
        return null;
    enforceEx!MYX(lcb.value <= uint.max, "Protocol Length Coded String is too long");
    return cast(string)packet.consume(cast(size_t)lcb.value).idup;
}


/** Skips over n items, advances the array, and return the newly advanced array to allow method chaining
 * */
T[] skip(T)(ref T[] array, size_t n)
in
{
    assert(n <= array.length);
}
body
{
    array = array[n..$];
    return array;
}

/**
 * Converts a value into a sequence of bytes and fills the supplied array
 *
 * Parameters:
 * IsInt24 = If only the most significant 3 bytes from the value should be used
 * value = The value to add to array
 * array = The array we should add the values for. It has to be large enough, and the values are packed starting index 0
 */
void packInto(T, bool IsInt24 = false)(T value, ref ubyte[] array)
in
{
    static if(IsInt24)
        assert(array.length >= 3);
    else
        assert(array.length >= T.sizeof, "Not enough space to unpack "~T.stringof);
}
body
{
    static if(T.sizeof >= 1)
    {
        array[0] = cast(ubyte) (value >> 8*0) & 0xff;
    }
    static if(T.sizeof >= 2)
    {
        array[1] = cast(ubyte) (value >> 8*1) & 0xff;
    }
    static if(!IsInt24)
    {
        static if(T.sizeof >= 4)
        {
            array[2] = cast(ubyte) (value >> 8*2) & 0xff;
            array[3] = cast(ubyte) (value >> 8*3) & 0xff;
        }
        static if(T.sizeof >= 8)
        {
            array[4] = cast(ubyte) (value >> 8*4) & 0xff;
            array[5] = cast(ubyte) (value >> 8*5) & 0xff;
            array[6] = cast(ubyte) (value >> 8*6) & 0xff;
            array[7] = cast(ubyte) (value >> 8*7) & 0xff;
        }
    }
    else
    {
        array[2] = cast(ubyte) (value >> 8*2) & 0xff;
    }
}

ubyte[] packLength(size_t l, out size_t offset)
out(result)
{
    assert(result.length >= 1);
}
body
{
    ubyte[] t;
    if (!l)
    {
        t.length = 1;
        t[0] = 0;
    }
    else if (l <= 250)
    {
        t.length = 1+l;
        t[0] = cast(ubyte) l;
        offset = 1;
    }
    else if (l <= 0xffff) // 16-bit
    {
        t.length = 3+l;
        t[0] = 252;
        packInto(cast(ushort)l, t[1..3]);
        offset = 3;
    }
    else if (l < 0xffffff) // 24-bit
    {
        t.length = 4+l;
        t[0] = 253;
        packInto!(uint, true)(cast(uint)l, t[1..4]);
        offset = 4;
    }
    else // 64-bit
    {
        ulong u = cast(ulong) l;
        t.length = 9+l;
        t[0] = 254;
        u.packInto(t[1..9]);
        offset = 9;
    }
    return t;
}

ubyte[] packLCS(void[] a)
{
    size_t offset;
    ubyte[] t = packLength(a.length, offset);
    if (t[0])
        t[offset..$] = (cast(ubyte[]) a)[0..$];
    return t;
}

/+
unittest
{
    bool isnull;
    ubyte[] uba = [ 0xde, 0xcc, 0xbb, 0xaa, 0x99, 0x88, 0x77, 0x66, 0x55, 0x01, 0x00 ];
    ubyte* ps = uba.ptr;
    ubyte* ubp = uba.ptr;
    ulong ul = parseLCB(ubp, isnull);
    assert(ul == 0xde && !isnull && ubp == ps+1);
    ubp = ps;
    uba[0] = 251;
    ul = parseLCB(ubp, isnull);
    assert(ul == 0 && isnull && ubp == ps+1);
    ubp = ps;
    uba[0] = 252;
    ul = parseLCB(ubp, isnull);
    assert(ul == 0xbbcc && !isnull && ubp == ps+3);
    ubp = ps;
    uba[0] = 253;
    ul = parseLCB(ubp, isnull);
    assert(ul == 0xaabbcc && !isnull && ubp == ps+4);
    ubp = ps;
    uba[0] = 254;
    ul = parseLCB(ubp, isnull);
    assert(ul == 0x5566778899aabbcc && !isnull && ubp == ps+9);
    ubyte[] buf;
    buf.length = 0x2000200;
    buf[] = '\x01';
    buf[0] = 250;
    buf[1] = '<';
    buf[249] = '!';
    buf[250] = '>';
    ubp = buf.ptr;
    ubyte[] x = parseLCS(ubp, isnull);
    assert(x.length == 250 && x[0] == '<' && x[249] == '>');
    buf[] = '\x01';
    buf[0] = 252;
    buf[1] = 0xff;
    buf[2] = 0xff;
    buf[3] = '<';
    buf[0x10000] = '*';
    buf[0x10001] = '>';
    ubp = buf.ptr;
    x = parseLCS(ubp, isnull);
    assert(x.length == 0xffff && x[0] == '<' && x[0xfffe] == '>');
    buf[] = '\x01';
    buf[0] = 253;
    buf[1] = 0xff;
    buf[2] = 0xff;
    buf[3] = 0xff;
    buf[4] = '<';
    buf[0x1000001] = '*';
    buf[0x1000002] = '>';
    ubp = buf.ptr;
    x = parseLCS(ubp, isnull);
    assert(x.length == 0xffffff && x[0] == '<' && x[0xfffffe] == '>');
    buf[] = '\x01';
    buf[0] = 254;
    buf[1] = 0xff;
    buf[2] = 0x00;
    buf[3] = 0x00;
    buf[4] = 0x02;
    buf[5] = 0x00;
    buf[6] = 0x00;
    buf[7] = 0x00;
    buf[8] = 0x00;
    buf[9] = '<';
    buf[0x2000106] = '!';
    buf[0x2000107] = '>';
    ubp = buf.ptr;
    x = parseLCS(ubp, isnull);
    assert(x.length == 0x20000ff && x[0] == '<' && x[0x20000fe] == '>');
}
+/

/// Magic marker sent in the first byte of mysql results in response to auth or command packets
enum ResultPacketMarker : ubyte
{
    /** Server reports an error
     * See_Also: http://forge.mysql.com/wiki/MySQL_Internals_ClientServer_Protocol#Error_Packet
     */
    error   = 0xff,

    /** No error, no result set.
     * See_Also: http://forge.mysql.com/wiki/MySQL_Internals_ClientServer_Protocol#OK_Packet
     */
    ok      = 0x00,

    /** Server reports end of data
     * See_Also: http://forge.mysql.com/wiki/MySQL_Internals_ClientServer_Protocol#EOF_Packet
     */
    eof     = 0xfe,
}

/**
 * A struct representing an OK or Error packet
 * See_Also: http://forge.mysql.com/wiki/MySQL_Internals_ClientServer_Protocol#Types_Of_Result_Packets
 * OK packets begin with a zero byte - Error packets with 0xff
 */
struct OKErrorPacket
{
    bool     error;
    ulong    affected;
    ulong    insertID;
    ushort   serverStatus;
    ushort   warnings;
    char[5]  sqlState;
    string   message;

    this(ubyte[] packet)
    {
        if (packet.front == ResultPacketMarker.error)
        {
            packet.popFront(); // skip marker/field code
            error = true;

            enforceEx!MYX(packet.length > 2, "Malformed Error packet - Missing error code");
            serverStatus = packet.consume!short(); // error code into server state
            if (packet.front == cast(ubyte) '#') //4.1+ error packet
            {
                packet.popFront(); // skip 4.1 marker
                enforceEx!MYX(packet.length > 5, "Malformed Error packet - Missing SQL state");
                sqlState[] = cast(char[]) packet[0..5];
                packet = packet[5..$];
            }
        }
        else if(packet.front == ResultPacketMarker.ok)
        {
            packet.popFront(); // skip marker/field code

            enforceEx!MYX(packet.length > 1, "Malformed OK packet - Missing affected rows");
            auto lcb = packet.consumeIfComplete!LCB();
            assert(!lcb.isNull);
            assert(!lcb.isIncomplete);
            affected = lcb.value;

            enforceEx!MYX(packet.length > 1, "Malformed OK packet - Missing insert id");
            lcb = packet.consumeIfComplete!LCB();
            assert(!lcb.isNull);
            assert(!lcb.isIncomplete);
            insertID = lcb.value;

            enforceEx!MYX(packet.length > 2,
                    format("Malformed OK packet - Missing server status. Expected length > 2, got %d", packet.length));
            serverStatus = packet.consume!short();

            enforceEx!MYX(packet.length >= 2, "Malformed OK packet - Missing warnings");
            warnings = packet.consume!short();
        }
        else
            throw new MYX("Malformed OK/Error packet - Incorrect type of packet", __FILE__, __LINE__);

        // both OK and Error packets end with a message for the rest of the packet
        message = cast(string)packet.idup;
    }
}

/** Field Flags
 * See_Also: http://forge.mysql.com/wiki/MySQL_Internals_ClientServer_Protocol#Field_Packet
 */
enum FieldFlags : ushort
{
    NOT_NULL        = 0x0001,
    PRI_KEY         = 0x0002,
    UNIQUE_KEY      = 0x0004,
    MULTIPLE_KEY    = 0x0008,
    BLOB            = 0x0010,
    UNSIGNED        = 0x0020,
    ZEROFILL        = 0x0040,
    BINARY          = 0x0080,
    ENUM            = 0x0100,
    AUTO_INCREMENT  = 0x0200,
    TIMESTAMP       = 0x0400,
    SET             = 0x0800
}

/**
 * A struct representing a field (column) description packet
 *
 * These packets, one for each column are sent before the data of a result set,
 * followed by an EOF packet.
 *
 * See_Also: http://forge.mysql.com/wiki/MySQL_Internals_ClientServer_Protocol#Field_Packet
 */
struct FieldDescription
{
private:
    string   _db;
    string   _table;
    string   _originalTable;
    string   _name;
    string   _originalName;
    ushort   _charSet;
    uint     _length;
    SQLType  _type;
    FieldFlags _flags;
    ubyte    _scale;
    ulong    _deflt;
    uint     chunkSize;
    void delegate(ubyte[], bool) chunkDelegate;

public:
    /**
     * Construct a FieldDescription from the raw data packet
     *
     * Parameters: packet = The packet contents excluding the 4 byte packet header
     */
    this(ubyte[] packet)
    in
    {
        assert(packet.length);
    }
    out
    {
        assert(!packet.length, "not all bytes read during FieldDescription construction");
    }
    body
    {
        packet.skip(4); // Skip catalog - it's always 'def'
        _db             = packet.consume!LCS();
        _table          = packet.consume!LCS();
        _originalTable  = packet.consume!LCS();
        _name           = packet.consume!LCS();
        _originalName   = packet.consume!LCS();

        enforceEx!MYX(packet.length >= 13, "Malformed field specification packet");
        packet.popFront(); // one byte filler here
        _charSet    = packet.consume!short();
        _length     = packet.consume!int();
        _type       = cast(SQLType)packet.consume!ubyte();
        _flags      = cast(FieldFlags)packet.consume!short();
        _scale      = packet.consume!ubyte();
        packet.skip(2); // two byte filler

        if(packet.length)
        {
            packet.skip(1); // one byte filler
            auto lcb = packet.consumeIfComplete!LCB();
            assert(!lcb.isNull);
            assert(!lcb.isIncomplete);
            _deflt = lcb.value;
        }
    }

    /// Database name for column as string
    @property string db() { return _db; }

    /// Table name for column as string - this could be an alias as in 'from tablename as foo'
    @property string table() { return _table; }

    /// Real table name for column as string
    @property string originalTable() { return _originalTable; }

    /// Column name as string - this could be an alias
    @property string name() { return _name; }

    /// Real column name as string
    @property string originalName() { return _originalName; }

    /// The character set in force
    @property ushort charSet() { return _charSet; }

    /// The 'length' of the column as defined at table creation
    @property uint length() { return _length; }

    /// The type of the column hopefully (but not always) corresponding to enum SQLType. Only the low byte currently used
    @property SQLType type() { return _type; }

    /// Column flags - unsigned, binary, null and so on
    @property FieldFlags flags() { return _flags; }

    /// Precision for floating point values
    @property ubyte scale() { return _scale; }

    /// NotNull from flags
    @property bool notNull() { return (_flags & FieldFlags.NOT_NULL) != 0; }

    /// Unsigned from flags
    @property bool unsigned() { return (_flags & FieldFlags.UNSIGNED) != 0; }

    /// Binary from flags
    @property bool binary() { return (_flags & FieldFlags.BINARY) != 0; }

    /// Is-enum from flags
    @property bool isenum() { return (_flags & FieldFlags.ENUM) != 0; }

    /// Is-set (a SET column that is) from flags
    @property bool isset() { return (_flags & FieldFlags.SET) != 0; }

    void show()
    {
        writefln("%s %d %x %016b", _name, _length, _type, _flags);
    }
}

/**
 * A struct representing a prepared statement parameter description packet
 *
 * These packets, one for each parameter are sent in response to the prepare command,
 * followed by an EOF packet.
 *
 * Sadly it seems that this facility is only a stub. The correct number of packets is sent,
 * but they contain no useful information and are all the same.
 */
struct ParamDescription
{
private:
    ushort _type;
    FieldFlags _flags;
    ubyte _scale;
    uint _length;

public:
    this(ubyte[] packet)
    {
        _type   = packet.consume!short();
        _flags  = cast(FieldFlags)packet.consume!short();
        _scale  = packet.consume!ubyte();
        _length = packet.consume!int();
        assert(!packet.length);
    }
    @property uint length() { return _length; }
    @property ushort type() { return _type; }
    @property FieldFlags flags() { return _flags; }
    @property ubyte scale() { return _scale; }
    @property bool notNull() { return (_flags & FieldFlags.NOT_NULL) != 0; }
    @property bool unsigned() { return (_flags & FieldFlags.UNSIGNED) != 0; }
}

bool isEOFPacket(ubyte[] packet)
{
    return packet.front == ResultPacketMarker.eof && packet.length < 9;
}

/**
 * A struct representing an EOF packet from the server
 *
 * An EOF packet is sent from the server after each sequence of field
 * description and parameter description packets, and after a sequence of
 * result set row packets.
 * An EOF packet is also called "Last Data Packet" or "End Packet".
 *
 * These EOF packets contain a server status and a warning count.
 *
 * See_Also: http://forge.mysql.com/wiki/MySQL_Internals_ClientServer_Protocol#EOF_Packet
 */
struct EOFPacket
{
private:
    ushort _warnings;
    ushort _serverStatus;

public:

   /**
    * Construct an EOFPacket struct from the raw data packet
    *
    * Parameters: packet = The packet contents excluding the 4 byte packet header
    */
    this(ubyte[] packet)
    in
    {
        assert(packet.isEOFPacket());
        assert(packet.length == 5);
    }
    out
    {
        assert(!packet.length);
    }
    body
    {
        packet.popFront(); // eof marker
        _warnings = packet.consume!short();
        _serverStatus = packet.consume!short();
    }

    /// Retrieve the warning count
    @property ushort warnings()     { return _warnings; }

    /// Retrieve the server status
    @property ushort serverStatus() { return _serverStatus; }
}

/**
 * A struct representing the collation of a sequence of FieldDescription packets.
 *
 * This data gets filled in after a query (prepared or otherwise) that creates a result set completes.
 * All the FD packets, and an EOF packet must be eaten before the row data packets can be read.
 */
struct ResultSetHeaders
{
private:
    FieldDescription[] _fieldDescriptions;
    string[] _fieldNames;
    ushort _warnings;

public:

    /**
     * Construct a ResultSetHeaders struct from a sequence of FieldDescription packets and an EOF packet.
     *
     * Parameters:
     *    con = A Connection via which the packets are read
     *    fieldCount = the number of fields/columns generated by the query
     */
    this(Connection con, uint fieldCount)
    {
        _fieldNames.length = _fieldDescriptions.length = fieldCount;
        foreach (uint i; 0 .. fieldCount)
        {
            auto packet = con.getPacket();
            enforceEx!MYX(!packet.isEOFPacket(),
                    "Expected field description packet, got EOF packet in result header sequence");

            _fieldDescriptions[i]   = FieldDescription(packet);
            _fieldNames[i]          = _fieldDescriptions[i]._name;
        }
        auto packet = con.getPacket();
        enforceEx!MYX(packet.isEOFPacket(),
                "Expected EOF packet in result header sequence");
        auto eof = EOFPacket(packet);
        con._serverStatus = eof._serverStatus;
        _warnings = eof._warnings;
    }

    /**
     * Add specialization information to one or more field descriptions.
     *
     * Currently the only specialization supported is the capability to deal with long data
     * e.g. BLOB or TEXT data in chunks by stipulating a chunkSize and a delegate to sink
     * the data.
     *
     * Parameters:
     *    csa = An array of ColumnSpecialization structs
     */
    void addSpecializations(ColumnSpecialization[] csa)
    {
        foreach(CSN csn; csa)
        {
            enforceEx!MYX(csn.cIndex < fieldCount && _fieldDescriptions[csn.cIndex].type == csn.type,
                    "Column specialization index or type does not match the corresponding column.");
            _fieldDescriptions[csn.cIndex].chunkSize = csn.chunkSize;
            _fieldDescriptions[csn.cIndex].chunkDelegate = csn.chunkDelegate;
        }
    }

    /// Index into the set of field descriptions
    FieldDescription opIndex(size_t i) { return _fieldDescriptions[i]; }
    /// Get the number of fields in a result row.
    @property fieldCount() { return _fieldDescriptions.length; }
    /// Get the warning count as per the EOF packet
    @property ushort warnings() { return _warnings; }
    /// Get an array of strings representing the column names
    @property string[] fieldNames() { return _fieldNames; }

    void show()
    {
        foreach (FieldDescription fd; _fieldDescriptions)
            fd.show();
    }
}

/**
 * A struct representing the collation of a prepared statement parameter description sequence
 *
 * As noted above - parameter descriptions are not fully implemented by MySQL.
 */
struct PreparedStmtHeaders
{
private:
    Connection _con;
    ushort _colCount, _paramCount;
    FieldDescription[] _colDescriptions;
    ParamDescription[] _paramDescriptions;
    ushort _warnings;

    bool getEOFPacket()
    {
        auto packet = _con.getPacket();
        if (!packet.isEOFPacket())
            return false;
        EOFPacket eof = EOFPacket(packet);
        _con._serverStatus = eof._serverStatus;
        _warnings += eof._warnings;
        return true;
    }

public:
    this(Connection con, ushort cols, ushort params)
    {
        _con = con;
        _colCount = cols;
        _paramCount = params;
        _colDescriptions.length = cols;
        _paramDescriptions.length = params;

        // The order in which fields are sent is params first, followed by EOF, then cols followed by EOF
        // The parameter specs are useless - they are all the same. This observation is coroborated
        // by the fact that the C API does not have any information about parameter types either.
        // WireShark gives up on these records also.
        foreach (uint i; 0.._paramCount)
            _con.getPacket();  // just eat them - they are not useful

        if (_paramCount)
            enforceEx!MYX(getEOFPacket(), "Expected EOF packet in result header sequence");

        foreach(uint i; 0.._colCount)
           _colDescriptions[i] = FieldDescription(_con.getPacket());

        if (_colCount)
            enforceEx!MYX(getEOFPacket(), "Expected EOF packet in result header sequence");
    }

    ParamDescription param(size_t i) { return _paramDescriptions[i]; }
    FieldDescription col(size_t i) { return _colDescriptions[i]; }

    @property paramCount() { return _paramCount; }
    @property ushort warnings() { return _warnings; }

    void showCols()
    {
        writefln("%d columns", _colCount);
        foreach (FieldDescription fd; _colDescriptions)
        {
            writefln("%10s %10s %10s %10s %10s %d %d %02x %016b %d",
                    fd._db, fd._table, fd._originalTable, fd._name, fd._originalName,
                    fd._charSet, fd._length, fd._type, fd._flags, fd._scale);
        }
    }
}


/// Set packet length and number. It's important that the length of packet has
/// already been set to the final state as its length is used
void setPacketHeader(ref ubyte[] packet, ubyte packetNumber)
in
{
    // packet should include header, and possibly data
    assert(packet.length >= 4);
}
body
{
    auto dataLength = packet.length - 4; // don't include header in calculated size
    assert(dataLength <= uint.max);
    packet.setPacketHeader(packetNumber, cast(uint)dataLength);
}

void setPacketHeader(ref ubyte[] packet, ubyte packetNumber, uint dataLength)
in
{
    // packet should include header
    assert(packet.length >= 4);
    // Length is always a 24-bit int
    assert(dataLength <= 0xffff_ffff_ffff);
}
body
{
    dataLength.packInto!(uint, true)(packet);
    packet[3] = packetNumber;
}

/**
 * A struct representing a database connection.
 *
 * The Connection is responsible for handshaking with the server to establish authentication.
 * It then passes client preferences to the server, and subsequently is the channel for all
 * command packets that are sent, and all response packets received.
 *
 * Uncompressed packets consist of a 4 byte header - 3 bytes of length, and one byte as a packet
 * number. Connection deals with the headers and ensures that packet numbers are sequential.
 *
 * The initial packet is sent by the server - esentially a 'hello' packet inviting login. That packet
 * has a sequence number of zero. That sequence number is the incremented by cliemt and server
 * packets thruogh the handshake sequence.
 *
 * After login all further sequences are initialized by the client sending a command packet with a
 * zero sequence number, to which the server replies with zero or more packets with sequential
 * sequence numbers.
 */
class Connection : EventedObject
{
protected:
    enum OpenState
    {
        /// We have not yet connected to the server, or have sent QUIT to the server and closed the connection
        notConnected,
        /// We have connected to the server and parsed the greeting, but not yet authenticated
        connected,
        /// We have successfully authenticated against the server, and need to send QUIT to the server when closing the connection
        authenticated
    }
    OpenState     _open;
    TcpConnection _socket;

    SvrCapFlags _sCaps, _cCaps;
    uint    _sThread;
    ushort  _serverStatus;
    ubyte   _sCharSet, _protocol;
    string  _serverVersion;

    string _host, _user, _pwd, _db;
    ushort _port;

    // This tiny thing here is pretty critical. Pay great attention to it's maintenance, otherwise
    // you'll get the dreaded "packet out of order" message. It, and the socket connection are
    // the reason why most other objects require a connection object for their construction.
    ubyte _cpn; /// Packet Number in packet header. Serial number to ensure correct ordering. First packet should have 0
    @property ubyte pktNumber()   { return _cpn; }
    void bumpPacket()       { _cpn++; }
    void resetPacket()      { _cpn = 0; }

    ubyte[] getPacket()
    {
        ubyte[4] header;
        _socket.read(header);
        // number of bytes always set as 24-bit
        uint numDataBytes = (header[2] << 16) + (header[1] << 8) + header[0];
        enforceEx!MYX(header[3] == pktNumber, "Server packet out of order");
        bumpPacket();

        ubyte[] packet = new ubyte[numDataBytes];
        _socket.read(packet);
        assert(packet.length == numDataBytes, "Wrong number of bytes read");
        return packet;
    }

    void send(ubyte[] packet)
    in
    {
        assert(packet.length > 4); // at least 1 byte more than header
    }
    body
    {
        _socket.write(packet);
    }

    void send(ubyte[] header, ubyte[] data)
    in
    {
        assert(header.length == 4 || header.length == 5/*command type included*/);
    }
    body
    {
        _socket.write(header);
        if(data.length)
            _socket.write(data);
    }

    void sendCmd(T)(CommandType cmd, T[] data)
    in
    {
        // Internal thread states. Clients shouldn't use this
        assert(cmd != CommandType.SLEEP);
        assert(cmd != CommandType.CONNECT);
        assert(cmd != CommandType.TIME);
        assert(cmd != CommandType.DELAYED_INSERT);
        assert(cmd != CommandType.CONNECT_OUT);

        // Deprecated
        assert(cmd != CommandType.CREATE_DB);
        assert(cmd != CommandType.DROP_DB);
        assert(cmd != CommandType.TABLE_DUMP);

        // cannot send more than uint.max bytes. TODO: better error message if we try?
        assert(data.length <= uint.max);
    }
    out
    {
        // at this point we should have sent a command
        assert(pktNumber == 1);
    }
    body
    {
        resetPacket();

        ubyte[] header;
        header.length = 4 /*header*/ + 1 /*cmd*/;
        header.setPacketHeader(pktNumber, cast(uint)data.length +1/*cmd byte*/);
        header[4] = cmd;
        bumpPacket();

        send(header, cast(ubyte[])data);
    }

    OKErrorPacket getCmdResponse(bool asString = false)
    {
        auto okp = OKErrorPacket(getPacket());
        enforceEx!MYX(!okp.error, "MySQL error: " ~ cast(string) okp.message);
        _serverStatus = okp.serverStatus;
        return okp;
    }

    ubyte[] buildAuthPacket(ubyte[] token)
    in
    {
        assert(token.length == 20);
    }
    body
    {
        ubyte[] packet;
        packet.reserve(4/*header*/ + 4 + 4 + 1 + 23 + _user.length+1 + token.length+1 + _db.length+1);
        packet.length = 4 + 4 + 4; // create room for the beginning headers that we set rather than append

        // NOTE: we'll set the header last when we know the size

        // Set the default capabilities required by the client
        _cCaps.packInto(packet[4..8]);

        // Request a conventional maximum packet length.
        1.packInto(packet[8..12]);

        packet ~= 33; // Set UTF-8 as default charSet

        // There's a statutory block of zero bytes here - fill them in.
        foreach(i; 0 .. 23)
            packet ~= 0;

        // Add the user name as a null terminated string
        foreach(i; 0 .. _user.length)
            packet ~= _user[i];
        packet ~= 0; // \0

        // Add our calculated authentication token as a length prefixed string.
        assert(token.length <= ubyte.max);
        packet ~= cast(ubyte)token.length;
        foreach(i; 0 .. token.length)
            packet ~= token[i];

        if(_db.length)
        {
            foreach(i; 0 .. _db.length)
                packet ~= _db[i];
            packet ~= 0; // \0
        }

        // The server sent us a greeting with packet number 0, so we send the auth packet
        // back with the next number.
        packet.setPacketHeader(pktNumber);
        bumpPacket();
        return packet;
    }

    void consumeServerInfo(ref ubyte[] packet)
    {
        _sCaps = cast(SvrCapFlags)packet.consume!ushort(); // server_capabilities (lower bytes)
        _sCharSet = packet.consume!ubyte(); // server_language
        _serverStatus = packet.consume!ushort(); //server_status
        _sCaps += cast(SvrCapFlags)(packet.consume!ushort() << 16); // server_capabilities (upper bytes)
        _sCaps |= SvrCapFlags.OLD_LONG_PASSWORD; // Assumed to be set since v4.1.1, according to spec

        enforceEx!MYX(_sCaps & SvrCapFlags.PROTOCOL41, "Server doesn't support protocol v4.1");
        enforceEx!MYX(_sCaps & SvrCapFlags.SECURE_CONNECTION, "Server doesn't support protocol v4.1 connection");
    }

    ubyte[] parseGreeting()
    {
        ubyte[] packet = getPacket();

        _protocol = packet.consume!ubyte();

        _serverVersion = packet.consume!string(packet.countUntil(0));
        packet.skip(1); // \0 terminated _serverVersion

        _sThread = packet.consume!uint();

        // read first part of scramble buf
        ubyte[] authBuf;
        authBuf.length = 255;
        authBuf[0..8] = packet.consume(8); // scramble_buff

        enforceEx!MYX(packet.consume!ubyte() == 0, "filler should always be 0");

        consumeServerInfo(packet);

        packet.skip(1); // this byte supposed to be scramble length, but is actually zero
        packet.skip(10); // filler of \0

        // rest of the scramble
        auto len = packet.countUntil(0);
        enforceEx!MYX(len >= 12, "second part of scramble buffer should be at least 12 bytes");
        enforce(authBuf.length > 8+len);
        authBuf[8..8+len] = packet.consume(len);
        authBuf.length = 8+len; // cut to correct size
        enforceEx!MYX(packet.consume!ubyte() == 0, "Excepted \\0 terminating scramble buf");

        return authBuf;
    }

    void init_connection()
    {
        _socket = connectTcp(_host, _port);
        //_socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVBUF, (1 << 24)-1);
        //int rbs;
        //_socket.getOption(SocketOptionLevel.SOCKET, SocketOption.RCVBUF, rbs);
        //_rbs = rbs;
    }

    ubyte[] makeToken(ubyte[] authBuf)
    {
        SHA1 sha1;
        sha1.reset();
        sha1.input(cast(const(ubyte)*) _pwd.ptr, _pwd.length);

        ubyte[] pass1 = sha1.result();
        sha1.reset();
        sha1.input(pass1.ptr, pass1.length);

        ubyte[] pass2 = sha1.result();
        sha1.reset();
        sha1.input(authBuf.ptr, authBuf.length);
        sha1.input(pass2.ptr, pass2.length);

        ubyte[] result = sha1.result();
        foreach (uint i; 0..20)
            result[i] = result[i] ^ pass1[i];
        return result;
    }

    SvrCapFlags getCommonCapabilities(SvrCapFlags server, SvrCapFlags client) pure
    {
        SvrCapFlags common;
        uint filter = 1;
        foreach (uint i; 0..uint.sizeof)
        {
            bool serverSupport = (server & filter) != 0; // can the server do this capability?
            bool clientSupport = (client & filter) != 0; // can we support it?
            if(serverSupport && clientSupport)
                common |= filter;
            filter <<= 1; // check next flag
        }
        return common;
    }

    void setClientFlags(SvrCapFlags capFlags)
    {
        _cCaps = getCommonCapabilities(_sCaps, capFlags);

        // We cannot operate in <4.1 protocol, so we'll force it even if the user
        // didn't supply it
        _cCaps |= SvrCapFlags.PROTOCOL41;
        _cCaps |= SvrCapFlags.SECURE_CONNECTION;
    }

    static string[] parseConnectionString(string cs)
    {
        string[] rv;
        rv.length = 4;
        string[] a = split(cs, ";");
        foreach (s; a)
        {
            string[] a2 = split(s, "=");
            enforceEx!MYX(a2.length == 2, "Bad connection string: " ~ cs);
            string name = strip(a2[0]);
            string val = strip(a2[1]);
            switch (name)
            {
                case "host":
                    rv[0] = val;
                    break;
                case "user":
                    rv[1] = val;
                    break;
                case "pwd":
                    rv[2] = val;
                    break;
                case "db":
                    rv[3] = val;
                    break;
                case "port":
                    rv[4] = val;
                    break;
                default:
                    throw new MYX("Bad connection string: " ~ cs, __FILE__, __LINE__);
            }
        }
        return rv;
    }

    void authenticate(ubyte[] greeting)
    in
    {
        assert(_open == OpenState.connected);
    }
    out
    {
        assert(_open == OpenState.authenticated);
    }
    body
    {
        auto token = makeToken(greeting);
        auto authPacket = buildAuthPacket(token);
        send(authPacket);

        auto packet = getPacket();
        auto okp = OKErrorPacket(packet);
        enforceEx!MYX(!okp.error, "Authentication failure: " ~ cast(string) okp.message);
        _open = OpenState.authenticated;
    }

    void connect(SvrCapFlags clientCapabilities)
    in
    {
        assert(_open == OpenState.notConnected);
    }
    out
    {
        assert(_open == OpenState.authenticated);
    }
    body
    {
        init_connection();
        auto greeting = parseGreeting();
        _open = OpenState.connected;

        setClientFlags(clientCapabilities);
        authenticate(greeting);
    }

    ~this()
    {
        if (_open != OpenState.notConnected)
            close();
    }

public:

    /**
     * Construct opened connection.
     *
     * After the connection is created, and the initial invitation is received from the server
     * client preferences can be set, and authentication can then be attempted.
     *
     * Parameters:
     *    host = An IP address in numeric dotted form, or as a host  name.
     *    user = The user name to authenticate.
     *    password = Users password.
     *    db = Desired initial database.
     *    capFlags = The set of flag bits from the server's capabilities that the client requires
     */
    this(string host, string user, string pwd, string db, ushort port = 3306, SvrCapFlags capFlags = defaultClientFlags)
    {
        enforceEx!MYX(capFlags & SvrCapFlags.PROTOCOL41, "This client only supports protocol v4.1");
        enforceEx!MYX(capFlags & SvrCapFlags.SECURE_CONNECTION, "This client only supports protocol v4.1 connection");

        _host = host;
        _user = user;
        _pwd = pwd;
        _db = db;
        _port = port;

        connect(capFlags);
    }

    /**
     * Construct opened connection.
     *
     * After the connection is created, and the initial invitation is received from the server
     * client preferences are set, and authentication can then be attempted.
     *
     * TBD The connection string needs work to allow for semicolons in its parts!
     *
     * Parameters:
     *    cs = A connetion string of the form "host=localhost;user=user;pwd=password;db=mysqld"
     *    capFlags = The set of flag bits from the server's capabilities that the client requires
     */
    this(string cs, SvrCapFlags capFlags = defaultClientFlags)
    {
        string[] a = parseConnectionString(cs);
        this(a[0], a[1], a[2], a[3], to!ushort(a[4]), capFlags);
    }

    @property bool closed()
    {
        return _open == OpenState.notConnected || !_socket.connected;
    }

   void acquire() { if( _socket ) _socket.acquire(); }
   void release() { if( _socket ) _socket.release(); }
   bool isOwner() { return _socket ? _socket.isOwner() : false; }

    /**
     * Explicitly close the connection.
     *
     * This is a two-stage process. First tell the server we are quitting this connection, and
     * then close the socket.
     *
     * Idiomatic use as follows is suggested:
     * ------------------
     * {
     *     auto con = Connection("localhost:user:password:mysqld");
     *     scope(exit) con.close();
     *     // Use the connection
     *     ...
     * }
     * ------------------
     */
    void close()
    {
        if (_open == OpenState.authenticated && _socket.connected)
            quit();

        if (_open == OpenState.connected)
        {
            if(_socket.connected)
                _socket.close();
            _open = OpenState.notConnected;
        }
        resetPacket();
    }

    private void quit()
    in
    {
        assert(_open == OpenState.authenticated);
    }
    body
    {
        sendCmd(CommandType.QUIT, []);
        // No response is sent for a quit packet
        _open = OpenState.connected;
    }

    /**
     * Select a current database.
     *
     * Params: dbName = Name of the requested database
     * Throws: MySQLException
     */
    void selectDB(string dbName)
    {
        sendCmd(CommandType.INIT_DB, dbName);
        getCmdResponse();
        _db = dbName;
    }

    /**
     * Check the server status
     *
     * Returns: An OKErrorPacket from which server status can be determined
     * Throws: MySQLException
     */
    OKErrorPacket pingServer()
    {
        sendCmd(CommandType.PING, []);
        return getCmdResponse();
    }

    /**
     * Refresh some feature(s) of the server.
     *
     * Returns: An OKErrorPacket from which server status can be determined
     * Throws: MySQLException
     */
    OKErrorPacket refreshServer(RefreshFlags flags)
    {
        sendCmd(CommandType.REFRESH, [flags]);
        return getCmdResponse();
    }

    /**
     * Get a textual report on the server status.
     *
     * (COM_STATISTICS)
     */
    string serverStats()
    {
        sendCmd(CommandType.STATISTICS, []);
        return cast(string) getPacket();
    }

    /**
     * Enable multiple statement commands
     *
     * This can be used later if this feature was not requested in the client capability flags.
     *
     * Params: on = Boolean value to turn the capability on or off.
     */
    void enableMultiStatements(bool on)
    {
        ubyte[] t;
        t.length = 2;
        t[0] = on ? 0 : 1;
        t[1] = 0;
        sendCmd(CommandType.STMT_OPTION, cast(string) t);

        // For some reason this command gets an EOF packet as response
        auto packet = getPacket();
        enforceEx!MYX(packet[0] == 254 && packet.length == 5, "Unexpected response to SET_OPTION command");
    }

    /// Return the in-force protocol number
    @property ubyte protocol() { return _protocol; }
    /// Server version
    @property string serverVersion() { return _serverVersion; }
    /// Server capability flags
    @property uint serverCapabilities() { return _sCaps; }
    /// Server status
    @property ushort serverStatus() { return _serverStatus; }
    /// Current character set
    @property ubyte charSet() { return _sCharSet; }
    /// Current database
    @property string currentDB() { return _db; }
}

/+
unittest
{
    bool ok = true;
    try
    {
        auto c = new Connection("host=localhost;user=user;pwd=password;db=mysqld");
        scope(exit) c.close();
        // These may vary according to the server setup
        assert(c.protocol == 10);
        assert(c.serverVersion == "5.1.54-1ubuntu4");
        assert(c.serverCapabilities == 0b1111011111111111);
        assert(c.serverStatus == 2);
        assert(c.charSet == 8);
        try {
            c.selectDB("rabbit");
        }
        catch (Exception x)
        {
            assert(x.msg.indexOf("Access denied") > 0);
        }
        auto okp = c.pingServer();
        assert(okp.serverStatus == 2);
        try {
            okp = c.refreshServer(RefreshFlags.GRANT);
        }
        catch (Exception x)
        {
            assert(x.msg.indexOf("Access denied") > 0);
        }
        string stats = c.serverStats();
        assert(stats.indexOf("Uptime") == 0);
        c.enableMultiStatements(true);   // Need to be tested later with a prepared "CALL"
        c.enableMultiStatements(false);
    }
    catch (Exception x)
    {
        writefln("(%s: %s) %s", x.file, x.line, x.msg);
        ok = false;
    }
    assert(ok);
}
+/

/**
 * A struct to represent specializations of prepared statement parameters.
 *
 * There are two specializations. First you can set an isNull flag to indicate that the
 * parameter is to have the SQL NULL value.
 *
 * Second, if you need to send large objects to the database it might be convenient to
 * send them in pieces. These two variables allow for this. If both are provided
 * then the corresponding column will be populated by calling the delegate repeatedly.
 * the source should fill the indicated slice with data and arrange for the delegate to
 * return the length of the data supplied. Af that is less than the chunkSize
 * then the chunk will be assumed to be the last one.
 */
struct ParameterSpecialization
{
    uint pIndex;    //parameter number 0 - number of params-1
    bool isNull;
    SQLType type = SQLType.INFER_FROM_D_TYPE;
    uint chunkSize;
    uint delegate(ubyte[]) chunkDelegate;
}
alias ParameterSpecialization PSN;

/**
 * A struct to represent specializations of prepared statement parameters.
 *
 * If you are executing a query that will include result columns that are large objects
 * it may be expedient to deal with the data as it is received rather than first buffering
 * it to some sort of byte array. These two variables allow for this. If both are provided
 * then the corresponding column will be fed to the stipulated delegate in chunks of
 * chunkSize, with the possible exception of the last chunk, which may be smaller.
 * The 'finished' argument will be set to true when the last chunk is set.
 *
 * Be aware when specifying types for column specializations that for some reason the
 * field descriptions returned for a resultset have all of the types TINYTEXT, MEDIUMTEXT,
 * TEXT, LONGTEXT, TINYBLOB, MEDIUMBLOB, BLOB, and LONGBLOB lumped as type 0xfc
 * contrary to what it says in the protocol documentation.
 */
struct ColumnSpecialization
{
    uint    cIndex;    // parameter number 0 - number of params-1
    ushort  type;
    uint    chunkSize;
    void delegate(ubyte[] chunk, bool finished) chunkDelegate;
}
alias ColumnSpecialization CSN;

/**
 * A struct to represent a single row of a result set.
 *
 * The row struct is used for both 'traditional' and 'prepared' result sets. It consists of parallel arrays
 * of Variant and bool, with the bool array indicating which of the result set columns are NULL.
 *
 * I have been agitating for some kind of null indicator that can be set for a Variant without destroying
 * its inherent type information. If this were the case, then the bool array could disappear.
 */
struct Row
{
private:
    Variant[]   _values;
    bool[]      _nulls;

    private static uint calcBitmapLength(uint fieldCount) pure nothrow
    {
        return (fieldCount+7+2)/8;
    }

    static bool[] consumeNullBitmap(ref ubyte[] packet, uint fieldCount)
    {
        uint bitmapLength = calcBitmapLength(fieldCount);
        enforceEx!MYX(packet.length >= bitmapLength, "Packet too small to hold null bitmap for all fields");
        auto bitmap = packet.consume(bitmapLength);
        return decodeNullBitmap(bitmap, fieldCount);
    }

    // This is to decode the bitmap in a binary result row. First two bits are skipped
    static bool[] decodeNullBitmap(ubyte[] bitmap, uint numFields)
    in
    {
        assert(bitmap.length >= calcBitmapLength(numFields),
                "bitmap not large enough to store all null fields");
    }
    out(result)
    {
        assert(result.length == numFields);
    }
    body
    {
        bool[] nulls;
        nulls.length = numFields;

        // the current byte we are processing for nulls
        ubyte bits = bitmap.front();
        // strip away the first two bits as they are reserved
        bits >>= 2;
        // .. and then we only have 6 bits left to process for this byte
        ubyte bitsLeftInByte = 6;
        foreach(ref isNull; nulls)
        {
            assert(bitsLeftInByte <= 8);
            // processed all bits? fetch new byte
            if (bitsLeftInByte == 0)
            {
                assert(bits == 0, "not all bits are processed!");
                assert(!bitmap.empty, "bits array too short for number of columns");
                bitmap.popFront();
                bits = bitmap.front;
                bitsLeftInByte = 8;
            }
            assert(bitsLeftInByte > 0);
            isNull = (bits & 0b0000_0001) != 0;

            // get ready to process next bit
            bits >>= 1;
            --bitsLeftInByte;
        }
        return nulls;
    }

public:

    /**
     * A constructor to extract the column data from a row data packet.
     *
     * If the data for the row exceeds the server's maximum packet size, then several packets will be
     * sent for the row that taken together constitute a logical row data packet. The logic of the data
     * recovery for a Row attempts to minimize the quantity of data that is bufferred. Users can assist
     * in this by specifying chunked data transfer in cases where results sets can include long
     * column values.
     *
     * The row struct is used for both 'traditional' and 'prepared' result sets. It consists of parallel arrays
     * of Variant and bool, with the bool array indicating which of the result set columns are NULL.
     *
     * I have been agitating for some kind of null indicator that can be set for a Variant without destroying
     * its inherent type information. If this were the case, then the bool array could disappear.
     */
    this(Connection con, ref ubyte[] packet, ResultSetHeaders rh, bool binary)
    in
    {
        assert(rh.fieldCount <= uint.max);
    }
    body
    {
        uint fieldCount = cast(uint)rh.fieldCount;
        _values.length = _nulls.length = fieldCount;

        if (binary)
        {
            // There's a null byte header on a binary result sequence, followed by some bytes of bitmap
            // indicating which columns are null
            enforceEx!MYX(packet.front == 0, "Expected null header byte for binary result row");
            packet.popFront();
            _nulls = consumeNullBitmap(packet, fieldCount);
        }

        foreach (int i; 0..fieldCount)
        {
            if(binary && _nulls[i])
                continue;

            SQLValue sqlValue;
            do
            {
                FieldDescription fd = rh[i];
                sqlValue = packet.consumeIfComplete(fd.type, binary, fd.unsigned);
                // TODO: Support chunk delegate
                if(sqlValue.isIncomplete)
                    packet ~= con.getPacket();
            } while(sqlValue.isIncomplete);
            assert(!sqlValue.isIncomplete);

            if(sqlValue.isNull)
            {
                assert(!binary);
                assert(!_nulls[i]);
                _nulls[i] = true;
            }
            else
            {
                _values[i] = sqlValue.value;
            }
        }
    }

    /**
     * Simplify retrieval of a column value by index.
     *
     * If the table you are working with does not allow NULL columns, this may be all you need. Otherwise
     * you will have to use isNull(i) as well.
     *
     * Params: i = the zero based index of the column whose value is required.
     * Returns: A Variant holding the column value.
     */
    Variant opIndex(uint i)
    {
        enforceEx!MYX(i < _nulls.length, format("Cannot get column %d of %d. Index out of bounds", i, _nulls.length));
        enforceEx!MYX(!_nulls[i], format("Column %s is null, check for isNull", i));
        return _values[i];
    }

    /**
     * Check if a column in the result row was NULL
     *
     * Params: i = The zero based column index.
     */
    @property bool isNull(uint i) { return _nulls[i]; }

    /**
     * Move the content of the row into a compatible struct
     *
     * This method takes no account of NULL column values. If a column was NULL, the corresponding
     * Variant value would be unchanged in those cases.
     *
     * The method will throw if the type of the Variant is not implicitly convertible to the corresponding
     * struct member
     *
     * Params: S = a struct type.
     *                s = an ref instance of the type
     */
    void toStruct(S)(ref S s) if (is(S == struct))
    {
        foreach (i, dummy; s.tupleof)
        {
            if(_nulls[i])
                s.tupleof[i] = typeof(s.tupleof[i]).init;
            else
            {
                enforceEx!MYX(_values[i].convertsTo!(typeof(s.tupleof[i]))(),
                    "At col "~to!string(i)~" the value is not implicitly convertible to the structure type");
                s.tupleof[i] = _values[i].get!(typeof(s.tupleof[i]));
            }
        }
    }

    void show()
    {
        foreach(Variant v; _values)
            writef("%s, ", v.toString());
        writeln("");
    }
}

/**
 * Composite representation of a column value
 *
 * Another case where a null flag on Variant would simplify matters.
 */
struct DBValue
{
    Variant value;
    bool isNull;
}

/**
 * A Random access range of Rows.
 *
 * This is the entity that is returned by the Command methods execSQLResult and
 * execPreparedResult
 *
 * MySQL result sets can be up to 2^^64 rows, and the 32 bit implementation of the
 * MySQL C API accomodates such potential massive result sets by storing the rows in
 * a doubly linked list. I have taken the view that users who have a need for result sets
 * up to this size should be working with a 64 bit system, and as such the 32 bit
 * implementation will throw if the number of rows exceeds the 32 bit size_t.max.
 */
struct ResultSet
{
private:
    Row[]       _rows;      // all rows in ResultSet, we store this to be able to revert() to it's original state
    string[]    _colNames;
    Row[]       _curRows;   // current rows in ResultSet

    this (Row[] rows, string[] colNames)
    {
        _rows = rows;
        _curRows = _rows[];
        _colNames = colNames;
    }

public:
    /**
     * Make the ResultSet behave as a random access range - empty
     *
     */
    @property bool empty() { return _curRows.length == 0; }

    /**
     * Make the ResultSet behave as a random access range - save
     *
     */
    @property ResultSet save()
    {
        return this;
    }

    /**
     * Make the ResultSet behave as a random access range - front
     *
     * Gets the first row in whatever remains of the Range.
     */
    @property Row front()
    {
        enforceEx!MYX(_curRows.length, "Attempted to get front of an empty ResultSet");
        return _curRows[0];
    }

    /**
     * Make the ResultSet behave as a random access range - back
     *
     * Gets the last row in whatever remains of the Range.
     */
    @property Row back()
    {
        enforceEx!MYX(_curRows.length, "Attempted to get back on an empty ResultSet");
        return _curRows[$-1];
    }

    /**
     * Make the ResultSet behave as a random access range - popFront()
     *
     */
    void popFront()
    {
        enforceEx!MYX(_curRows.length, "Attempted to popFront() on an empty ResultSet");
        _curRows = _curRows[1..$];
    }

    /**
     * Make the ResultSet behave as a random access range - popBack
     *
     */
    void popBack()
    {
        enforceEx!MYX(_curRows.length, "Attempted to popBack() on an empty ResultSet");
        _curRows = _curRows[0 .. $-1];
    }

    /**
     * Make the ResultSet behave as a random access range - opIndex
     *
     * Gets the i'th row of whatever remains of the range
     */
    Row opIndex(size_t i)
    {
        enforceEx!MYX(_curRows.length, "Attempted to index into an empty ResultSet range.");
        enforceEx!MYX(i < _curRows.length, "Requested range index out of range");
        return _curRows[i];
    }

    /**
     * Make the ResultSet behave as a random access range - length
     *
     */
    @property size_t length() { return _curRows.length; }

    /**
     * Restore the range to its original span.
     *
     * Since the range is just a view of the data, we can easily revert to the
     * initial state.
     */
    void revert()
    {
        _curRows = _rows[];
    }

    /**
     * Get a row as an associative array by column name
     *
     * The row in question will be that which was the most recent subject of
     * front, back, or opIndex. If there have been no such references it will be front.
     */
    DBValue[string] asAA()
    {
        enforceEx!MYX(_curRows.length, "Attempted use of empty ResultSet as an associative array.");
        DBValue[string] aa;
        foreach (uint i, string s; _colNames)
        {
            DBValue value;
            value.value  = front._values[i];
            value.isNull = front._nulls[i];
            aa[s]        = value;
        }
        return aa;
    }
}

/**
 * An input range of Rows.
 *
 * This is the entity that is returned by the Command methods execSQLSequence and
 * execPreparedSequence
 *
 * MySQL result sets can be up to 2^^64 rows. This interface allows for iteration through
 * a result set of that size.
 */
struct ResultSequence
{
private:
    Command*    _cmd;
    Row         _row; // current row
    string[]    _colNames;
    ulong       _numRowsFetched;
    bool        _empty;

    this (Command* cmd, string[] colNames)
    {
        _cmd        = cmd;
        _colNames   = colNames;
        popFront();
    }

    invariant()
    {
        assert(!_empty && _cmd); // command must exist while not empty
    }

public:
    ~this()
    {
        close();
    }

    /**
     * Make the ResultSequence behave as an input range - empty
     *
     */
    @property bool empty() { return _empty; }

    /**
     * Make the ResultSequence behave as an input range - front
     *
     * Gets the current row
     */
    @property Row front()
    {
        enforceEx!MYX(!_empty, "Attempted 'front' on exhausted result sequence.");
        return _row;
    }

    /**
     * Make the ResultSequence behave as am input range - popFront()
     *
     * Progresses to the next row of the result set - that will then be 'front'
     */
    void popFront()
    {
        enforceEx!MYX(!_empty, "Attempted 'popFront' when no more rows available");
        _row = _cmd.getNextRow();
        /+
        if (!_row._valid)
            _empty = true;
        else
            +/
            _numRowsFetched++;
    }

    /**
     * Get the current row as an associative array by column name
     */
     DBValue[string] asAA()
     {
        enforceEx!MYX(!_empty, "Attempted 'front' on exhausted result sequence.");
        DBValue[string] aa;
        foreach (uint i, string s; _colNames)
        {
            DBValue value;
            value.value  = _row._values[i];
            value.isNull = _row._nulls[i];
            aa[s]        = value;
        }
        return aa;
     }

    /**
     * Explicitly clean up the MySQL resources and cancel pending results
     *
     */
    void close()
    {
        if(_cmd)
            _cmd.purgeResult();
        _empty = true; // small hack to throw an exception rather than using a closed command
        _cmd = null;
    }

    /**
     * Get the number of currently retrieved.
     *
     * Note that this is not neccessarlly the same as the length of the range.
     */
     @property ulong rowCount() { return _numRowsFetched; }
}

/**
 * Encapsulation of an SQL command or query.
 *
 * A Command be be either a one-off SQL query, or may use a prepared statement.
 * Commands that are expected to return a result set - queries - have distinctive methods
 * that are enforced. That is it will be an error to call such a method with an SQL command
 * that does not produce a result set.
 */
struct Command
{
private:
    Connection _con;
    string _sql;
    uint _hStmt;
    ulong _insertID;
    bool _rowsPending, _headersPending, _pendingBinary, _rebound;
    ushort _psParams, _psWarnings, _fieldCount;
    ResultSetHeaders _rsh;
    PreparedStmtHeaders _psh;
    Variant[] _inParams;
    ParameterSpecialization[] _psa;
    string _prevFunc;

    bool sendCmd(CommandType cmd)
    {
        enforceEx!MYX(!(_headersPending || _rowsPending),
            "There are result set elements pending - purgeResult() required.");

        _con.sendCmd(cmd, _sql);
        return true;
    }

    static ubyte[] makeBitmap(ParameterSpecialization[] psa)
    {
        size_t bml = (psa.length+7)/8;
        ubyte[] bma;
        bma.length = bml;
        foreach (uint i, PSN psn; psa)
        {
            if (!psn.isNull)
                continue;
            uint bn = i/8;
            uint bb = i%8;
            ubyte sr = 1;
            sr <<= bb;
            bma[bn] |= sr;
        }
        return bma;
    }

    ubyte[] makePSPrefix(ubyte flags = 0)
    {
        ubyte[] prefix;
        prefix.length = 14;

        prefix[4] = CommandType.STMT_EXECUTE;
        _hStmt.packInto(prefix[5..9]);
        prefix[9] = flags;   // flags, no cursor
        prefix[10] = 1; // iteration count - currently always 1
        prefix[11] = 0;
        prefix[12] = 0;
        prefix[13] = 0;

        return prefix;
    }

    ubyte[] analyseParams(out ubyte[] vals, out bool longData)
    {
        size_t pc = _inParams.length;
        ubyte[] types;
        types.length = pc*2;
        size_t alloc = pc*20;
        vals.length = alloc;
        uint vcl = 0, len;
        int ct = 0;

        void reAlloc(size_t n)
        {
            if (vcl+n < alloc)
                return;
            size_t inc = (alloc*3)/2;
            if (inc <  n)
                inc = n;
            alloc += inc;
            vals.length = alloc;
        }

        foreach (size_t i; 0..pc)
        {
            if (_psa[i].chunkSize)
                longData= true;
            bool isnull = _psa[i].isNull;
            Variant v = _inParams[i];
            SQLType ext = _psa[i].type;
            string ts = v.type.toString();
            bool isRef;
            if (ts[$-1] == '*')
            {
                ts.length = ts.length-1;
                isRef= true;
            }

            enum UNSIGNED  = 0x80;
            enum SIGNED    = 0;
            switch (ts)
            {
                case "bool":
                    if (ext == SQLType.INFER_FROM_D_TYPE)
                        types[ct++] = SQLType.BIT;
                    else
                        types[ct++] = cast(ubyte) ext;
                    types[ct++] = SIGNED;
                    if (isnull) break;
                    reAlloc(2);
                    bool bv = isRef? *(v.get!(bool*)): v.get!(bool);
                    vals[vcl++] = 1;
                    vals[vcl++] = bv? 0x31: 0x30;
                    break;
                case "byte":
                    types[ct++] = SQLType.TINY;
                    types[ct++] = SIGNED;
                    if (isnull) break;
                    reAlloc(1);
                    vals[vcl++] = isRef? *(v.get!(byte*)): v.get!(byte);
                    break;
                case "ubyte":
                    types[ct++] = SQLType.TINY;
                    types[ct++] = UNSIGNED;
                    if (isnull) break;
                    reAlloc(1);
                    vals[vcl++] = isRef? *(v.get!(ubyte*)): v.get!(ubyte);
                    break;
                case "short":
                    types[ct++] = SQLType.SHORT;
                    types[ct++] = SIGNED;
                    if (isnull) break;
                    reAlloc(2);
                    short si = isRef? *(v.get!(short*)): v.get!(short);
                    vals[vcl++] = cast(ubyte) (si & 0xff);
                    vals[vcl++] = cast(ubyte) ((si >> 8) & 0xff);
                    break;
                case "ushort":
                    types[ct++] = SQLType.SHORT;
                    types[ct++] = UNSIGNED;
                    reAlloc(2);
                    ushort us = isRef? *(v.get!(ushort*)): v.get!(ushort);
                    vals[vcl++] = cast(ubyte) (us & 0xff);
                    vals[vcl++] = cast(ubyte) ((us >> 8) & 0xff);
                    break;
                case "int":
                    types[ct++] = SQLType.INT;
                    types[ct++] = SIGNED;
                    if (isnull) break;
                    reAlloc(4);
                    int ii = isRef? *(v.get!(int*)): v.get!(int);
                    vals[vcl++] = cast(ubyte) (ii & 0xff);
                    vals[vcl++] = cast(ubyte) ((ii >> 8) & 0xff);
                    vals[vcl++] = cast(ubyte) ((ii >> 16) & 0xff);
                    vals[vcl++] = cast(ubyte) ((ii >> 24) & 0xff);
                    break;
                case "uint":
                    types[ct++] = SQLType.INT;
                    types[ct++] = UNSIGNED;
                    if (isnull) break;
                    reAlloc(4);
                    uint ui = isRef? *(v.get!(uint*)): v.get!(uint);
                    vals[vcl++] = cast(ubyte) (ui & 0xff);
                    vals[vcl++] = cast(ubyte) ((ui >> 8) & 0xff);
                    vals[vcl++] = cast(ubyte) ((ui >> 16) & 0xff);
                    vals[vcl++] = cast(ubyte) ((ui >> 24) & 0xff);
                    break;
                case "long":
                    types[ct++] = SQLType.LONGLONG;
                    types[ct++] = SIGNED;
                    if (isnull) break;
                    reAlloc(8);
                    long li = isRef? *(v.get!(long*)): v.get!(long);
                    vals[vcl++] = cast(ubyte) (li & 0xff);
                    vals[vcl++] = cast(ubyte) ((li >> 8) & 0xff);
                    vals[vcl++] = cast(ubyte) ((li >> 16) & 0xff);
                    vals[vcl++] = cast(ubyte) ((li >> 24) & 0xff);
                    vals[vcl++] = cast(ubyte) ((li >> 32) & 0xff);
                    vals[vcl++] = cast(ubyte) ((li >> 40) & 0xff);
                    vals[vcl++] = cast(ubyte) ((li >> 48) & 0xff);
                    vals[vcl++] = cast(ubyte) ((li >> 56) & 0xff);
                    break;
                case "ulong":
                    types[ct++] = SQLType.LONGLONG;
                    types[ct++] = UNSIGNED;
                    if (isnull) break;
                    reAlloc(8);
                    ulong ul = isRef? *(v.get!(ulong*)): v.get!(ulong);
                    vals[vcl++] = cast(ubyte) (ul & 0xff);
                    vals[vcl++] = cast(ubyte) ((ul >> 8) & 0xff);
                    vals[vcl++] = cast(ubyte) ((ul >> 16) & 0xff);
                    vals[vcl++] = cast(ubyte) ((ul >> 24) & 0xff);
                    vals[vcl++] = cast(ubyte) ((ul >> 32) & 0xff);
                    vals[vcl++] = cast(ubyte) ((ul >> 40) & 0xff);
                    vals[vcl++] = cast(ubyte) ((ul >> 48) & 0xff);
                    vals[vcl++] = cast(ubyte) ((ul >> 56) & 0xff);
                    break;
                case "float":
                    types[ct++] = SQLType.FLOAT;
                    types[ct++] = SIGNED;
                    if (isnull) break;
                    reAlloc(4);
                    float f = isRef? *(v.get!(float*)): v.get!(float);
                    ubyte* ubp = cast(ubyte*) &f;
                    vals[vcl++] = *ubp++;
                    vals[vcl++] = *ubp++;
                    vals[vcl++] = *ubp++;
                    vals[vcl++] = *ubp;
                    break;
                case "double":
                    types[ct++] = SQLType.DOUBLE;
                    types[ct++] = SIGNED;
                    if (isnull) break;
                    reAlloc(8);
                    double d = isRef? *(v.get!(double*)): v.get!(double);
                    ubyte* ubp = cast(ubyte*) &d;
                    vals[vcl++] = *ubp++;
                    vals[vcl++] = *ubp++;
                    vals[vcl++] = *ubp++;
                    vals[vcl++] = *ubp++;
                    vals[vcl++] = *ubp++;
                    vals[vcl++] = *ubp++;
                    vals[vcl++] = *ubp++;
                    vals[vcl++] = *ubp;
                    break;
                case "std.datetime.Date":
                    types[ct++] = SQLType.DATE;
                    types[ct++] = SIGNED;
                    Date date = isRef? *(v.get!(Date*)): v.get!(Date);
                    ubyte[] da = pack(date);
                    size_t l = da.length;
                    if (isnull) break;
                    reAlloc(l);
                    vals[vcl..vcl+l] = da[];
                    vcl += l;
                    break;
                case "std.datetime.Time":
                    types[ct++] = SQLType.TIME;
                    types[ct++] = SIGNED;
                    TimeOfDay time = isRef? *(v.get!(TimeOfDay*)): v.get!(TimeOfDay);
                    ubyte[] ta = pack(time);
                    size_t l = ta.length;
                    if (isnull) break;
                    reAlloc(l);
                    vals[vcl..vcl+l] = ta[];
                    vcl += l;
                    break;
                case "std.datetime.DateTime":
                    types[ct++] = SQLType.DATETIME;
                    types[ct++] = SIGNED;
                    DateTime dt = isRef? *(v.get!(DateTime*)): v.get!(DateTime);
                    ubyte[] da = pack(dt);
                    size_t l = da.length;
                    if (isnull) break;
                    reAlloc(l);
                    vals[vcl..vcl+l] = da[];
                    vcl += l;
                    break;
                case "connect.Timestamp":
                    types[ct++] = SQLType.TIMESTAMP;
                    types[ct++] = SIGNED;
                    Timestamp tms = isRef? *(v.get!(Timestamp*)): v.get!(Timestamp);
                    DateTime dt = toDateTime(tms.rep);
                    ubyte[] da = pack(dt);
                    size_t l = da.length;
                    if (isnull) break;
                    reAlloc(l);
                    vals[vcl..vcl+l] = da[];
                    vcl += l;
                    break;
                case "immutable(char)[]":
                    if (ext == SQLType.INFER_FROM_D_TYPE)
                        types[ct++] = SQLType.VARCHAR;
                    else
                        types[ct++] = cast(ubyte) ext;
                    types[ct++] = SIGNED;
                    if (isnull) break;
                    string s = isRef? *(v.get!(string*)): v.get!(string);
                    ubyte[] packed = packLCS(cast(void[]) s);
                    reAlloc(packed.length);
                    vals[vcl..vcl+packed.length] = packed[];
                    vcl += packed.length;
                    break;
                case "char[]":
                    if (ext == SQLType.INFER_FROM_D_TYPE)
                        types[ct++] = SQLType.VARCHAR;
                    else
                        types[ct++] = cast(ubyte) ext;
                    types[ct++] = SIGNED;
                    if (isnull) break;
                    char[] ca = isRef? *(v.get!(char[]*)): v.get!(char[]);
                    ubyte[] packed = packLCS(cast(void[]) ca);
                    reAlloc(packed.length);
                    vals[vcl..vcl+packed.length] = packed[];
                    vcl += packed.length;
                    break;
                case "byte[]":
                    if (ext == SQLType.INFER_FROM_D_TYPE)
                        types[ct++] = SQLType.TINYBLOB;
                    else
                        types[ct++] = cast(ubyte) ext;
                    types[ct++] = SIGNED;
                    if (isnull) break;
                    byte[] ba = isRef? *(v.get!(byte[]*)): v.get!(byte[]);
                    ubyte[] packed = packLCS(cast(void[]) ba);
                    reAlloc(packed.length);
                    vals[vcl..vcl+packed.length] = packed[];
                    vcl += packed.length;
                    break;
                case "ubyte[]":
                    if (ext == SQLType.INFER_FROM_D_TYPE)
                        types[ct++] = SQLType.TINYBLOB;
                    else
                        types[ct++] = cast(ubyte) ext;
                    types[ct++] = SIGNED;
                    if (isnull) break;
                    ubyte[] uba = isRef? *(v.get!(ubyte[]*)): v.get!(ubyte[]);
                    ubyte[] packed = packLCS(cast(void[]) uba);
                    reAlloc(packed.length);
                    vals[vcl..vcl+packed.length] = packed[];
                    vcl += packed.length;
                    break;
                default:
                    throw new MYX("Unsupported parameter type", __FILE__, __LINE__);
            }
        }
        vals.length = vcl;
        return types;
    }

    void sendLongData()
    {
        assert(_psa.length <= ushort.max); // parameter number is sent as short
        foreach (ushort i, PSN psn; _psa)
        {
            if (!psn.chunkSize) continue;
            uint cs = psn.chunkSize;
            uint delegate(ubyte[]) dg = psn.chunkDelegate;

            ubyte[] chunk;
            chunk.length = cs+11;
            chunk.setPacketHeader(0 /*each chunk is separate cmd*/);
            chunk[4] = CommandType.STMT_SEND_LONG_DATA;
            _hStmt.packInto(chunk[5..9]); // statement handle
            packInto(i, chunk[9..11]); // parameter number

            // byte 11 on is payload
            for (;;)
            {
                uint sent = dg(chunk[11..cs+11]);
                if (sent < cs)
                {
                    if (sent == 0)    // data was exact multiple of chunk size - all sent
                        break;
                    sent += 7;        // adjust for non-payload bytes
                    chunk.length = chunk.length - (cs-sent);     // trim the chunk
                    packInto!(uint, true)(cast(uint)sent, chunk[0..3]);
                    _con.send(chunk);
                    break;
                }
                _con.send(chunk);
            }
        }
    }

public:

    /**
     * Construct a naked Command object
     *
     * Params: con = A Connection object to communicate with the server
     */
    this(Connection con)
    {
        _con = con;
        _con.resetPacket();
    }

    /**
     * Construct a Command object complete with SQL
     *
     * Params: con = A Connection object to communicate with the server
     *                sql = SQL command string.
     */
    this(Connection con, string sql)
    {
        _sql = sql;
        this(con);
    }

    @property
    {
        /// Get the current SQL for the Command
        string sql() { return _sql; }

        /**
        * Set a new SQL command.
        *
        * This can have quite profound side effects. It resets the Command to an initial state.
        * If a query has been issued on the Command that produced a result set, then all of the
        * result set packets - field description sequence, EOF packet, result rows sequence, EOF packet
        * must be flushed from the server before any further operation can be performed on
        * the Connection. If you want to write speedy and efficient MySQL programs, you should
        * bear this in mind when designing your queries so that you are not requesting many
        * rows when one would do.
        *
        * Params: sql = SQL command string.
        */
        string sql(string sql)
        {
            purgeResult();
            releaseStatement();
            _con.resetPacket();
            return _sql = sql;
        }
    }

    /**
     * Submit an SQL command to the server to be compiled into a prepared statement.
     *
     * The result of a successful outcome will be a statement handle - an ID - for the prepared statement,
     * a count of the parameters required for excution of the statement, and a count of the columns
     * that will be present in any result set that the command generates. Thes values will be stored in
     * in the Command struct.
     *
     * The server will then proceed to send prepared statement headers, including parameter descriptions,
     * and result set field descriptions, followed by an EOF packet.
     *
     * If there is an existing statement handle in the Command struct, that prepared statement is released.
     *
     * Throws: MySQLEXception if there are pending result set items, or if the server has a problem.
     */
    void prepare()
    {
        enforceEx!MYX(!(_headersPending || _rowsPending),
            "There are result set elements pending - purgeResult() required.");

        if (_hStmt)
            releaseStatement();
        _con.sendCmd(CommandType.STMT_PREPARE, _sql);
        _fieldCount = 0;

        ubyte[] packet = _con.getPacket();
        if (packet.front == ResultPacketMarker.ok)
        {
            packet.popFront();
            _hStmt              = packet.consume!int();
            _fieldCount         = packet.consume!short();
            _psParams           = packet.consume!short();

            _inParams.length    = _psParams;
            _psa.length         = _psParams;

            packet.popFront(); // one byte filler
            _psWarnings         = packet.consume!short();

            // At this point the server also sends field specs for parameters and columns if there were any of each
            _psh = PreparedStmtHeaders(_con, _fieldCount, _psParams);
        }
        else if(packet.front == ResultPacketMarker.error)
        {
            auto error = OKErrorPacket(packet);
            throw new MYX("MySQL Error: " ~ cast(string) error.message, __FILE__, __LINE__);
        }
        else
            assert(0); // FIXME: what now?
    }

    /**
     * Release a prepared statement.
     *
     * This method tells the server that it can dispose of the information it holds about the
     * current prepared statement, and resets the Command object to an initial state in
     * that respect.
     */
    void releaseStatement()
    {
        ubyte[] packet;
        packet.length = 9;
        packet.setPacketHeader(0/*packet number*/);
        _con.bumpPacket();
        packet[4] = CommandType.STMT_CLOSE;
        _hStmt.packInto(packet[5..9]);
        purgeResult();
        _con.send(packet);
        // It seems that the server does not find it necessary to send a response
        // for this command.
        _hStmt = 0;
    }

    /**
     * Flush any outstanding result set elements.
     *
     * When the server responds to a command that produces a result set, it queues the whole set
     * of corresponding packets over the current connection. Before that Connection can embark on
     * any new command, it must receive all of those packets and junk them.
     * http://www.mysqlperformanceblog.com/2007/07/08/mysql-net_write_timeout-vs-wait_timeout-and-protocol-notes/
     */
    ulong purgeResult()
    {
        ulong rows = 0;
        if (_fieldCount)
        {
            if (_headersPending)
            {
                for (uint i = 0;; i++)
                {
                    if (_con.getPacket().isEOFPacket())
                    {
                        _headersPending = false;
                        break;
                    }
                    enforceEx!MYX(i < _fieldCount, "Field header count exceeded but no EOF packet found.");
                }
            }
            if (_rowsPending)
            {
                for (;;  rows++)
                {
                    if (_con.getPacket().isEOFPacket())
                    {
                        _rowsPending = _pendingBinary = false;
                        break;
                    }
                }
            }
        }
        _fieldCount = 0;
        _con.resetPacket();
        return rows;
    }

    /**
     * Bind a D variable to a prepared statement parameter.
     *
     * In this implementation, binding comprises setting a value into the appropriate element of
     * an array of Variants which represent the parameters, and setting any required specializations.
     *
     * To bind to some D variable, we set the corrsponding variant with its address, so there is no
     * need to rebind between calls to execPreparedXXX.
     */
    void bindParameter(T)(ref T val, uint pIndex, ParameterSpecialization psn = PSN(0, false, SQLType.INFER_FROM_D_TYPE, 0, null, true))
    {
        // Now in theory we should be able to check the parameter type here, since the protocol is supposed
        // to send us type information for the parameters, but this capability seems to be broken. This assertion
        // is supported by the fact that the same information is not available via the MySQL C API either. It is up
        // to the programmer to ensure that appropriate type information is embodied in the variant array, or
        // provided explicitly. This sucks, but short of having a client side SQL parser I don't see what can be done.
        //
        // We require that the statement be prepared at this point so we can at least check that the parameter
        // number is within the required range
        enforceEx!MYX(_hStmt, "The statement must be prepared before parameters are bound.");
        enforceEx!MYX(pIndex < _psParams, "Parameter number is out of range for the prepared statement.");
        _inParams[pIndex] = &val;
        if (!psn.dummy)
        {
            psn.pIndex = pIndex;
            _psa[pIndex] = psn;
        }
    }

    /**
     * Bind a tuple of D variables to the parameters of a prepared statement.
     *
     * You can use this method to bind a set of variables if you don't need any specialization,
     * that is there will be no null values, and chunked transfer is not neccessary.
     *
     * The tuple must match the required number of parameters, and it is the programmer's responsibility
     * to ensure that they are of appropriate types.
     */
    void bindParameterTuple(T...)(ref T args)
    {
        enforceEx!MYX(_hStmt, "The statement must be prepared before parameters are bound.");
        enforceEx!MYX(args.length == _psParams, "Argument list supplied does not match the number of parameters.");
        foreach (uint i, dummy; args)
            _inParams[i] = &args[i];
    }

    /**
     * Bind a Variant[] as the parameters of a prepared statement.
     *
     * You can use this method to bind a set of variables in Variant form to the parameters of a prepared statement.
     *
     * Parameter specializations can be added if required. This method could be used to add records from a data
     * entry form along the lines of
     * ------------
     * auto c = Command(con, "insert into table42 values(?, ?, ?)");
     * c.prepare();
     * Variant[] va;
     * va.length = 3;
     * c.bindParameters(va);
     * DataRecord dr;    // Some data input facility
     * ulong ra;
     * do
     * {
     *     dr.get();
     *     va[0] = dr("Name");
     *     va[1] = dr("City");
     *     va[2] = dr("Whatever");
     *     c.execPrepared(ra);
     * } while(tod < "17:30");
     * ------------
     * Params: va = External list of Variants to be used as parameters
     *                psnList = any required specializations
     */
    void bindParameters(Variant[] va, ParameterSpecialization[] psnList= null)
    {
        enforceEx!MYX(_hStmt, "The statement must be prepared before parameters are bound.");
        enforceEx!MYX(va.length == _psParams, "Param count supplied does not match prepared statement");
        _inParams[] = va[];
        if (psnList !is null)
        {
            foreach (PSN psn; psnList)
                _psa[psn.pIndex] = psn;
        }
    }

    /**
     * Access a prepared statement parameter for update.
     *
     * Another style of usage would simply update the parameter Variant directly
     *
     * ------------
     * c.param(0) = 42;
     * c.param(1) = "The answer";
     * ------------
     * Params: index = The zero based index
     */
    ref Variant param(uint index)
    {
        enforceEx!MYX(_hStmt, "The statement must be prepared before parameters are bound.");
        enforceEx!MYX(index < _psParams, "Parameter index out of range.");
        return _inParams[index];
    }

    /**
     * Execute a one-off SQL command.
     *
     * Use this method when you are not going to be using the same command repeatedly.
     * It can be used with commands that don't produce a result set, or those that do. If there is a result
     * set its existence will be indicated by the return value.
     *
     * Any result set can be accessed vis getNextRow(), but you should really be using execSQLResult()
     * or execSQLSequence() for such queries.
     *
     * Params: ra = An out parameter to receive the number of rows affected.
     * Returns: true if there was a (possibly empty) result set.
     */
    bool execSQL(out ulong ra)
    {
        _con.sendCmd(CommandType.QUERY, _sql);
        _fieldCount = 0;
        ubyte[] packet = _con.getPacket();
        bool rv;
        if (packet.front == ResultPacketMarker.ok || packet.front == ResultPacketMarker.error)
        {
            _con.resetPacket();
            auto okp = OKErrorPacket(packet);
            enforceEx!MYX(!okp.error, "MySQL Error: " ~ cast(string) okp.message);
            ra = okp.affected;
            _con._serverStatus = okp.serverStatus;
            _insertID = okp.insertID;
            rv = false;
        }
        else
        {
            // There was presumably a result set
            assert(packet.front >= 1 && packet.front <= 250); // ResultSet packet header should have this value
            _headersPending = _rowsPending = true;
            _pendingBinary = false;
            auto lcb = packet.consumeIfComplete!LCB();
            assert(!lcb.isNull);
            assert(!lcb.isIncomplete);
            _fieldCount = cast(ushort)lcb.value;
            assert(_fieldCount == lcb.value);
            rv = true;
            ra = 0;
        }
        return rv;
    }

    /**
     * Execute a one-off SQL command for the case where you expect a result set, and want it all at once.
     *
     * Use this method when you are not going to be using the same command repeatedly.
     * This method will throw if the SQL command does not produce a result set.
     *
     * If there are long data items among the expected result columns you can specify that they are to be
     * subject to chunked transfer via a delegate.
     *
     * Params: csa = An optional array of ColumnSpecialization structs.
     * Returns: A (possibly empty) ResultSet.
     */
    ResultSet execSQLResult(ColumnSpecialization[] csa = null)
    {
        ulong ra;
        enforceEx!MYX(execSQL(ra), "The executed query did not produce a result set.");
        _rsh = ResultSetHeaders(_con, _fieldCount);
        if (csa !is null)
            _rsh.addSpecializations(csa);
        _headersPending = false;

        Row[] rows;
        while(true)
        {
            auto packet = _con.getPacket();
            if(packet.isEOFPacket())
                break;
            rows ~= Row(_con, packet, _rsh, false);
            // As the row fetches more data while incomplete, it might already have
            // fetched the EOF marker, so we have to check it again
            if(packet.isEOFPacket())
                break;
        }
        _rowsPending = _pendingBinary = false;

        return ResultSet(rows, _rsh.fieldNames);
    }

    /**
     * Execute a one-off SQL command for the case where you expect a result set, and want
     * to deal with it a row at a time.
     *
     * Use this method when you are not going to be using the same command repeatedly.
     * This method will throw if the SQL command does not produce a result set.
     *
     * If there are long data items among the expected result columns you can specify that they are to be
     * subject to chunked transfer via a delegate.
     *
     * Params: csa = An optional array of ColumnSpecialization structs.
     * Returns: A (possibly empty) ResultSequence.
     */
    ResultSequence execSQLSequence(ColumnSpecialization[] csa = null)
    {
        uint alloc = 20;
        Row[] rra;
        rra.length = alloc;
        uint cr = 0;
        ulong ra;
        enforceEx!MYX(execSQL(ra), "The executed query did not produce a result set.");
        _rsh = ResultSetHeaders(_con, _fieldCount);
        if (csa !is null)
            _rsh.addSpecializations(csa);

        _headersPending = false;
        return ResultSequence(&this, _rsh.fieldNames);
    }

    /**
     * Execute a one-off SQL command to place result values into a set of D variables.
     *
     * Use this method when you are not going to be using the same command repeatedly.
     * It will throw if the specified command does not produce a result set, or if any column
     * type is incompatible with the corresponding D variable
     *
     * Params: args = A tuple of D variables to receive the results.
     * Returns: true if there was a (possibly empty) result set.
     */
    void execSQLTuple(T...)(ref T args)
    {
        ulong ra;
        enforceEx!MYX(execSQL(ra), "The executed query did not produce a result set.");
        Row rr = getNextRow();
        if (!rr._valid)   // The result set was empty - not a crime.
            return;
        enforceEx!MYX(rr._values.length == args.length, "Result column count does not match the target tuple.");
        foreach (uint i, dummy; args)
        {
            enforceEx!MYX(typeid(args[i]).toString() == rr._values[i].type.toString(),
                "Tuple "~to!string(i)~" type and column type are not compatible.");
            args[i] = rr._values[i].get!(typeof(args[i]));
        }
        // If there were more rows, flush them away
        // Question: Should I check in purgeResult and throw if there were - it's very inefficient to
        // allow sloppy SQL that does not ensure just one row!
        purgeResult();
    }

    /**
     * Execute a prepared command.
     *
     * Use this method when you will use the same SQL command repeatedly.
     * It can be used with commands that don't produce a result set, or those that do. If there is a result
     * set its existence will be indicated by the return value.
     *
     * Any result set can be accessed vis getNextRow(), but you should really be using execPreparedResult()
     * or execPreparedSequence() for such queries.
     *
     * Params: ra = An out parameter to receive the number of rows affected.
     * Returns: true if there was a (possibly empty) result set.
     */
    bool execPrepared(out ulong ra)
    {
        enforceEx!MYX(_hStmt, "The statement has not been prepared.");
        ubyte[] packet;
        _con.resetPacket();

        ubyte[] prefix = makePSPrefix(0);
        size_t len = prefix.length;
        bool longData;

        if (_psh._paramCount)
        {
            ubyte[] one = [ 1 ];
            ubyte[] vals;
            ubyte[] types = analyseParams(vals, longData);
            ubyte[] nbm = makeBitmap(_psa);
            packet = prefix ~ nbm ~ one ~ types ~ vals;
        }
        else
            packet = prefix;

        if (longData)
            sendLongData();

        assert(packet.length <= uint.max);
        packet.setPacketHeader(_con.pktNumber);
        _con.bumpPacket();
        _con.send(packet);
        packet = _con.getPacket();
        bool rv;
        if (packet.front == ResultPacketMarker.ok || packet.front == ResultPacketMarker.error)
        {
            _con.resetPacket();
            auto okp = OKErrorPacket(packet);
            enforceEx!MYX(!okp.error, "MySQL Error: " ~ cast(string) okp.message);
            ra = okp.affected;
            _con._serverStatus = okp.serverStatus;
            _insertID = okp.insertID;
            rv = false;
        }
        else
        {
            // There was presumably a result set
            _headersPending = _rowsPending = _pendingBinary = true;
            auto lcb = packet.consumeIfComplete!LCB();
            assert(!lcb.isIncomplete);
            _fieldCount = cast(ushort)lcb.value;
            rv = true;
        }
        return rv;
    }

    /**
     * Execute a prepared SQL command for the case where you expect a result set, and want it all at once.
     *
     * Use this method when you will use the same command repeatedly.
     * This method will throw if the SQL command does not produce a result set.
     *
     * If there are long data items among the expected result columns you can specify that they are to be
     * subject to chunked transfer via a delegate.
     *
     * Params: csa = An optional array of ColumnSpecialization structs.
     * Returns: A (possibly empty) ResultSet.
     */
    ResultSet execPreparedResult(ColumnSpecialization[] csa = null)
    {
        ulong ra;
        enforceEx!MYX(execPrepared(ra), "The executed query did not produce a result set.");
        uint alloc = 20;
        Row[] rra;
        rra.length = alloc;
        uint cr = 0;
        _rsh = ResultSetHeaders(_con, _fieldCount);
        if (csa !is null)
            _rsh.addSpecializations(csa);
        _headersPending = false;
        ubyte[] packet;
        for (uint i = 0;; i++)
        {
            packet = _con.getPacket();
            if (packet.isEOFPacket())
                break;
            Row row = Row(_con, packet, _rsh, true);
            if (cr >= alloc)
            {
                alloc = (alloc*3)/2;
                rra.length = alloc;
            }
            rra[cr++] = row;
        }
        _rowsPending = _pendingBinary = false;
        rra.length = cr;
        ResultSet rs = ResultSet(rra, _rsh.fieldNames);
        return rs;
    }

    /**
     * Execute a prepared SQL command for the case where you expect a result set, and want
     * to deal with it one row at a time.
     *
     * Use this method when you will use the same command repeatedly.
     * This method will throw if the SQL command does not produce a result set.
     *
     * If there are long data items among the expected result columns you can specify that they are to be
     * subject to chunked transfer via a delegate.
     *
     * Params: csa = An optional array of ColumnSpecialization structs.
     * Returns: A (possibly empty) ResultSequence.
     */
    ResultSequence execPreparedSequence(ColumnSpecialization[] csa = null)
    {
        ulong ra;
        enforceEx!MYX(execPrepared(ra), "The executed query did not produce a result set.");
        uint alloc = 20;
        Row[] rra;
        rra.length = alloc;
        uint cr = 0;
        _rsh = ResultSetHeaders(_con, _fieldCount);
        if (csa !is null)
            _rsh.addSpecializations(csa);
        _headersPending = false;
        return ResultSequence(&this, _rsh.fieldNames);
    }

    /**
     * Execute a prepared SQL command to place result values into a set of D variables.
     *
     * Use this method when you will use the same command repeatedly.
     * It will throw if the specified command does not produce a result set, or if any column
     * type is incompatible with the corresponding D variable
     *
     * Params: args = A tuple of D variables to receive the results.
     * Returns: true if there was a (possibly empty) result set.
     */
    void execPreparedTuple(T...)(ref T args)
    {
        ulong ra;
        enforceEx!MYX(execPrepared(ra), "The executed query did not produce a result set.");
        Row rr = getNextRow();
        enforceEx!MYX(rr._valid, "The result set was empty.");
        enforceEx!MYX(rr._values.length == args.length, "Result column count does not match the target tuple.");
        foreach (uint i, dummy; args)
        {
            enforceEx!MYX(typeid(args[i]).toString() == rr._values[i].type.toString(),
                "Tuple "~to!string(i)~" type and column type are not compatible.");
            args[i] = rr._values[i].get!(typeof(args[i]));
        }
        // If there were more rows, flush them away
        // Question: Should I check in purgeResult and throw if there were - it's very inefficient to
        // allow sloppy SQL that does not ensure just one row!
        purgeResult();
    }

    /**
     * Get the next Row of a pending result set.
     *
     * This method can be used after either execSQL() or execPrepared() have returned true
     * to retrieve result set rows sequentially.
     *
     * Similar functionality is available via execSQLSequence() and execPreparedSequence() in
     * which case the interface is presented as a forward range of Rows.
     *
     * This method allows you to deal with very large result sets either a row at a time, or by
     * feeding the rows into some suitable container such as a linked list.
     *
     * Returns: A Row object.
     */
    Row getNextRow()
    {
        if (_headersPending)
        {
            _rsh = ResultSetHeaders(_con, _fieldCount);
            _headersPending = false;
        }
        ubyte[] packet;
        Row rr;
        packet = _con.getPacket();
        if (packet.isEOFPacket())
        {
            _rowsPending = _pendingBinary = false;
            return rr;
        }
        if (_pendingBinary)
            rr = Row(_con, packet, _rsh, true);
        else
            rr = Row(_con, packet, _rsh, false);
        //rr._valid = true;
        return rr;
    }

    /**
     * Execute a stored function, with any required input variables, and store the return value into a D variable.
     *
     * For this method, no query string is to be provided. The required one is of the form "select foo(?, ? ...)".
     * The method generates it and the appropriate bindings - in, and out. Chunked transfers are not supported
     * in either direction. If you need them, create the parameters separately, then use execPreparedResult()
     * to get a one-row, one-column result set.
     *
     * If it is not possible to convert the column value to the type of target, then execFunction will throw.
     * If the result is NULL, that is indicated by a false return value, and target is unchanged.
     *
     * In the interest of performance, this method assumes that the user has the required information about
     * the number and types of IN parameters and the type of the output variable. In the same interest, if the
     * method is called repeatedly for the same stored function, prepare() is omitted after the first call.
     *
     * Params:
     *    T = The type of the variable to receive the return result.
     *    U = type tuple of arguments
     *    name = The name of the stored function.
     *    target = the D variable to receive the stored function return result.
     *    args = The list of D variables to act as IN arguments to the stored function.
     *
     */
    bool execFunction(T, U...)(string name, ref T target, U args)
    {
        bool repeatCall = (name == _prevFunc);
        enforceEx!MYX(repeatCall || _hStmt == 0, "You must not prepare the statement before calling execFunction");
        if (!repeatCall)
        {
            _sql = "select " ~ name ~ "(";
            bool comma = false;
            foreach (arg; args)
            {
                if (comma)
                    _sql ~= ",?";
                else
                {
                    _sql ~= "?";
                    comma = true;
                }
            }
            _sql ~= ")";
            prepare();
            _prevFunc = name;
        }
        bindParameterTuple(args);
        ulong ra;
        enforceEx!MYX(execPrepared(ra), "The executed query did not produce a result set.");
        Row rr = getNextRow();
        enforceEx!MYX(rr._valid, "The result set was empty.");
        enforceEx!MYX(rr._values.length == 1, "Result was not a single column.");
        enforceEx!MYX(typeid(target).toString() == rr._values[0].type.toString(),
                        "Target type and column type are not compatible.");
        if (!rr.isNull(0))
            target = rr._values[0].get!(T);
        // If there were more rows, flush them away
        // Question: Should I check in purgeResult and throw if there were - it's very inefficient to
        // allow sloppy SQL that does not ensure just one row!
        purgeResult();
        return !rr.isNull(0);
    }

    /**
     * Execute a stored procedure, with any required input variables.
     *
     * For this method, no query string is to be provided. The required one is of the form "call proc(?, ? ...)".
     * The method generates it and the appropriate in bindings. Chunked transfers are not supported.
     * If you need them, create the parameters separately, then use execPrepared() or execPreparedResult().
     *
     * In the interest of performance, this method assumes that the user has the required information about
     * the number and types of IN parameters. In the same interest, if the method is called repeatedly for the
     * same stored function, prepare() and other redundant operations are omitted after the first call.
     *
     * OUT parameters are not currently supported. It should generally be possible with MySQL to present
     * them as a result set.
     *
     * Params:
     *    T = Type tuple
     *    name = The name of the stored procedure.
     *    args = Tuple of args
     * Returns: True if the SP created a result set.
     */
    bool execProcedure(T...)(string name, ref T args)
    {
        bool repeatCall = (name == _prevFunc);
        enforceEx!MYX(repeatCall || _hStmt == 0, "You must not prepare a statement before calling execProcedure");
        if (!repeatCall)
        {
            _sql = "call " ~ name ~ "(";
            bool comma = false;
            foreach (arg; args)
            {
                if (comma)
                    _sql ~= ",?";
                else
                {
                    _sql ~= "?";
                    comma = true;
                }
            }
            _sql ~= ")";
            prepare();
            _prevFunc = name;
        }
        bindParameterTuple(args);
        ulong ra;
        return execPrepared(ra);
    }

    /// After a command that inserted a row into a table with an auto-increment  ID
    /// column, this method allows you to retrieve the last insert ID.
    @property ulong lastInsertID() { return _insertID; }
}

version(none) {
unittest
{
    struct X
    {
        int a, b, c;
        string s;
        double d;
    }
    bool ok = true;
    auto c = new Connection("localhost", "user", "password", "mysqld");
    scope(exit) c.close();
    try
    {
        ulong ra;
        auto c1 = Command(c);

        c1.sql = "delete from basetest";
        c1.execSQL(ra);

        c1.sql = "insert into basetest values(" ~
            "1, -128, 255, -32768, 65535, 42, 4294967295, -9223372036854775808, 18446744073709551615, 'ABC', " ~
            "'The quick brown fox', 0x000102030405060708090a0b0c0d0e0f, '2007-01-01', " ~
            "'12:12:12', '2007-01-01 12:12:12', 1.234567890987654, 22.4, NULL)";
        c1.execSQL(ra);

        c1.sql = "select bytecol from basetest limit 1";
        ResultSet rs = c1.execSQLResult();
        assert(rs.length == 1);
        assert(rs[0][0] == -128);
        c1.sql = "select ubytecol from basetest limit 1";
        rs = c1.execSQLResult();
        assert(rs.length == 1);
        assert(rs.front[0] == 255);
        c1.sql = "select shortcol from basetest limit 1";
        rs = c1.execSQLResult();
        assert(rs.length == 1);
        assert(rs[0][0] == short.min);
        c1.sql = "select ushortcol from basetest limit 1";
        rs = c1.execSQLResult();
        assert(rs.length == 1);
        assert(rs[0][0] == ushort.max);
        c1.sql = "select intcol from basetest limit 1";
        rs = c1.execSQLResult();
        assert(rs.length == 1);
        assert(rs[0][0] == 42);
        c1.sql = "select uintcol from basetest limit 1";
        rs = c1.execSQLResult();
        assert(rs.length == 1);
        assert(rs[0][0] == uint.max);
        c1.sql = "select longcol from basetest limit 1";
        rs = c1.execSQLResult();
        assert(rs.length == 1);
        assert(rs[0][0] == long.min);
        c1.sql = "select ulongcol from basetest limit 1";
        rs = c1.execSQLResult();
        assert(rs.length == 1);
        assert(rs[0][0] == ulong.max);
        c1.sql = "select charscol from basetest limit 1";
        rs = c1.execSQLResult();
        assert(rs.length == 1);
        assert(rs[0][0].toString() == "ABC");
        c1.sql = "select stringcol from basetest limit 1";
        rs = c1.execSQLResult();
        assert(rs.length == 1);
        assert(rs[0][0].toString() == "The quick brown fox");
        c1.sql = "select bytescol from basetest limit 1";
        rs = c1.execSQLResult();
        assert(rs.length == 1);
        assert(rs[0][0].toString() == "[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]");
        c1.sql = "select datecol from basetest limit 1";
        rs = c1.execSQLResult();
        assert(rs.length == 1);
        Date d = rs[0][0].get!(Date);
        assert(d.year == 2007 && d.month == 1 && d.day == 1);
        c1.sql = "select timecol from basetest limit 1";
        rs = c1.execSQLResult();
        assert(rs.length == 1);
        TimeOfDay t = rs[0][0].get!(TimeOfDay);
        assert(t.hour == 12 && t.minute == 12 && t.second == 12);
        c1.sql = "select dtcol from basetest limit 1";
        rs = c1.execSQLResult();
        assert(rs.length == 1);
        DateTime dt = rs[0][0].get!(DateTime);
        assert(dt.year == 2007 && dt.month == 1 && dt.day == 1 && dt.hour == 12 && dt.minute == 12 && dt.second == 12);
        c1.sql = "select doublecol from basetest limit 1";
        rs = c1.execSQLResult();
        assert(rs.length == 1);
        assert(rs[0][0].toString() == "1.23457");
        c1.sql = "select floatcol from basetest limit 1";
        rs = c1.execSQLResult();
        assert(rs.length == 1);
        assert(rs[0][0].toString() == "22.4");

        c1.sql = "select * from basetest limit 1";
        rs = c1.execSQLResult();
        assert(rs.length == 1);
        assert(rs[0][0] == true);
        assert(rs[0][1] == -128);
        assert(rs[0][2] == 255);
        assert(rs[0][3] == short.min);
        assert(rs[0][4] == ushort.max);
        assert(rs[0][5] == 42);
        assert(rs[0][6] == uint.max);
        assert(rs[0][7] == long.min);
        assert(rs[0][8] == ulong.max);
        assert(rs[0][9].toString() == "ABC");
        assert(rs[0][10].toString() == "The quick brown fox");
        assert(rs[0][11].toString() == "[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]");
        d = rs[0][12].get!(Date);
        assert(d.year == 2007 && d.month == 1 && d.day == 1);
        t = rs[0][13].get!(TimeOfDay);
        assert(t.hour == 12 && t.minute == 12 && t.second == 12);
        dt = rs[0][14].get!(DateTime);
        assert(dt.year == 2007 && dt.month == 1 && dt.day == 1 && dt.hour == 12 && dt.minute == 12 && dt.second == 12);
        assert(rs[0][15].toString() == "1.23457");
        assert(rs[0]._values[16].toString() == "22.4");
        assert(rs[0].isNull(17) == true);

        c1.sql = "select bytecol, ushortcol, intcol, charscol, floatcol from basetest limit 1";
        rs = c1.execSQLResult();
        X x;
        rs[0].toStruct(x);
        assert(x.a == -128 && x.b == 65535 && x.c == 42 && x.s == "ABC" && to!string(x.d) == "22.4");

        c1.sql = "select * from basetest limit 1";
        c1.prepare();
        rs = c1.execPreparedResult();
        assert(rs.length == 1);
        assert(rs[0][0] == true);
        assert(rs[0][1] == -128);
        assert(rs[0][2] == 255);
        assert(rs[0][3] == short.min);
        assert(rs[0][4] == ushort.max);
        assert(rs[0][5] == 42);
        assert(rs[0][6] == uint.max);
        assert(rs[0][7] == long.min);
        assert(rs[0][8] == ulong.max);
        assert(rs[0][9].toString() == "ABC");
        assert(rs[0][10].toString() == "The quick brown fox");
        assert(rs[0][11].toString() == "[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]");
        d = rs[0][12].get!(Date);
        assert(d.year == 2007 && d.month == 1 && d.day == 1);
        t = rs[0][13].get!(TimeOfDay);
        assert(t.hour == 12 && t.minute == 12 && t.second == 12);
        dt = rs[0][14].get!(DateTime);
        assert(dt.year == 2007 && dt.month == 1 && dt.day == 1 && dt.hour == 12 && dt.minute == 12 && dt.second == 12);
        assert(rs[0][15].toString() == "1.23457");
        assert(rs[0][16].toString() == "22.4");
        assert(rs[0]._nulls[17] == true);

        c1.sql = "insert into basetest (intcol, stringcol) values(?, ?)";
        c1.prepare();
        Variant[] va;
        va.length = 2;
        va[0] = 42;
        va[1] = "The quick brown fox x";
        c1.bindParameters(va);
        foreach (int i; 0..20)
        {
            c1.execPrepared(ra);
            c1.param(0) += 1;
            c1.param(1) ~= "x";
        }

        int a;
        string b;
        c1.sql = "select intcol, stringcol from basetest where bytecol=-128 limit 1";
        c1.execSQLTuple(a, b);
        assert(a == 42 && b == "The quick brown fox");

        c1.sql = "select intcol, stringcol from basetest where bytecol=? limit 1";
        c1.prepare();
        Variant[] va2;
        va2.length = 1;
        va2[0] = cast(byte) -128;
        c1.bindParameters(va2);
        a = 0;
        b = "";
        c1.execPreparedTuple(a, b);
        assert(a == 42 && b == "The quick brown fox");

        c1.sql = "update basetest set intcol=? where bytecol=-128";
        c1.prepare();
        int referred = 555;
        c1.bindParameter(referred, 0);
        c1.execPrepared(ra);
        referred = 666;
        c1.execPrepared(ra);
        c1.sql = "select intcol from basetest where bytecol = -128";
        int referredBack;
        c1.execSQLTuple(referredBack);
        assert(referredBack == 666);

        // Test execFunction()
        string g = "Gorgeous";
        string reply;
        c1.sql = "";
        bool nonNull = c1.execFunction("hello", reply, g);
        assert(nonNull && reply == "Hello Gorgeous!");
        g = "Hotlips";
        nonNull = c1.execFunction("hello", reply, g);
        assert(nonNull && reply == "Hello Hotlips!");

        // Test execProcedure()
        g = "inserted string 1";
        int m = 2001;
        c1.sql = "";
        c1.execProcedure("insert2", m, g);

        c1.sql = "select stringcol from basetest where intcol=2001";
        c1.execSQLTuple(reply);
        assert(reply == g);

        c1.sql = "delete from tblob";
        c1.execSQL(ra);
        c1.sql = "insert into tblob values(321, NULL, 22.4, NULL, '2011-11-05 11:52:00')";
        c1.execSQL(ra);

        uint delegate(ubyte[]) foo()
        {
            uint n = 20000000;
            uint cp = 0;

            void fill(ubyte[] a, uint m)
            {
                foreach (uint i; 0..m)
                {
                    a[i] = cast(ubyte) (cp & 0xff);
                    cp++;
                }
            }

            uint dg(ubyte[] dest)
            {
                uint len = dest.length;
                if (n >= len)
                {
                    fill(dest, len);
                    n -= len;
                    return len;
                }
                fill(dest, n);
                return n;
            }

            return &dg;
        }
/+
        c1.sql = "update tblob set lob=?, lob2=? where ikey=321";
        c1.prepare();
        ubyte[] uba;
        ubyte[] uba2;
        c1.bindParameter(uba, 0, PSN(0, false, SQLType.LONGBLOB, 10000, foo()));
        c1.bindParameter(uba2, 1, PSN(1, false, SQLType.LONGBLOB, 10000, foo()));
        c1.execPrepared(ra);

        uint got1, got2;
        bool verified1, verified2;
        void delegate(ubyte[], bool) bar1(ref uint got, ref bool  verified)
        {
          got = 0;
          verified = true;

          void dg(ubyte[] ba, bool finished)
          {
             foreach (uint; 0..ba.length)
             {
                if (verified && ba[i] != ((got+i) & 0xff))
                   verified = false;
             }
             got += ba.length;
          }
          return &dg;
        }

        void delegate(ubyte[], bool) bar2(ref uint got, ref bool  verified)
        {
          got = 0;
          verified = true;

          void dg(ubyte[] ba, bool finished)
          {
             foreach (uint i; 0..ba.length)
             {
                if (verified && ba[i] != ((got+i) & 0xff))
                   verified = false;
             }
             got += ba.length;
          }
          return &dg;
        }

        c1.sql = "select * from tblob limit 1";
        rs = c1.execSQLResult();
        ubyte[] blob = rs[0][1].get!(ubyte[]);
        ubyte[] blob2 = rs[0][3].get!(ubyte[]);
        DateTime dt4 = rs[0][4].get!(DateTime);
        writefln("blob. lengths %d %d", blob.length, blob2.length);
        writeln(to!string(dt4));


        c1.sql = "select * from tblob limit 1";
        CSN[] csa = [ CSN(1, 0xfc, 100000, bar1(got1, verified1)), CSN(3, 0xfc, 100000, bar2(got2, verified2)) ];
        rs = c1.execSQLResult(csa);
        writefln("1) %d, %s", got1, verified1);
        writefln("2) %d, %s", got2, verified2);
        DateTime dt4 = rs[0][4].get!(DateTime);
        writeln(to!string(dt4));
+/
    }
    catch (Exception x)
    {
        writefln("(%s: %s) %s", x.file, x.line, x.msg);
        ok = false;
    }
    assert(ok);
    writeln("Command unit tests completed OK.");
}
} // version(none)

/**
 * A struct to hold column metadata
 */
struct ColumnInfo
{
    /// The database that the table having this column belongs to.
    string schema;
    /// The table that this column belongs to.
    string table;
    /// The name of the column.
    string name;
    /// Zero based index of the column within a table row.
    uint index;
    /// Is the default value NULL?
    bool defaultNull;
    /// The default value as a string if not NULL
    string defaultValue;
    /// Can the column value be set to NULL
    bool nullable;
    /// What type is the column - tinyint, char, varchar, blob, date etc
    string type;
    /// Capacity in characters, -1L if not applicable
    long charsMax;
    /// Capacity in bytes - same as chars if not a unicode table definition, -1L if not applicable.
    long octetsMax;
    /// Presentation information for numerics, -1L if not applicable.
    short numericPrecision;
    /// Scale information for numerics or NULL, -1L if not applicable.
    short numericScale;
    /// Character set, "<NULL>" if not applicable.
    string charSet;
    /// Collation, "<NULL>" if not applicable.
    string collation;
    /// More detail about the column type, e.g. "int(10) unsigned".
    string colType;
    /// Information about the column's key status, blank if none.
    string key;
    /// Extra information.
    string extra;
    /// Privileges for logged in user.
    string privileges;
    /// Any comment that was set at table definition time.
    string comment;
}

/**
 * A struct to hold stored function metadata
 *
 */
struct MySQLProcedure
{
    string db;
    string name;
    string type;
    string definer;
    DateTime modified;
    DateTime created;
    string securityType;
    string comment;
    string charSetClient;
    string collationConnection;
    string collationDB;
}

/**
 * Facilities to recover meta-data from a connection
 *
 * It is important to bear in mind that the methods provided will only return the
 * information that is available to the connected user. This may well be quite limited.
 */
struct MetaData
{
private:
    Connection _con;

    MySQLProcedure[] stored(bool procs)
    {
        enforceEx!MYX(_con.currentDB.length, "There is no selected database");
        string query = procs ? "SHOW PROCEDURE STATUS WHERE db='": "SHOW FUNCTION STATUS WHERE db='";
        query ~= _con.currentDB ~ "'";

        auto cmd = Command(_con, query);
        auto rs = cmd.execSQLResult();
        MySQLProcedure[] pa;
        pa.length = rs.length;
        foreach (size_t i; 0..rs.length)
        {
            MySQLProcedure foo;
            Row r = rs[i];
            foreach (int j; 0..11)
            {
                if (r.isNull(j))
                    continue;
                auto value = r[j].toString();
                switch (j)
                {
                    case 0:
                        foo.db = value;
                        break;
                    case 1:
                        foo.name = value;
                        break;
                    case 2:
                        foo.type = value;
                        break;
                    case 3:
                        foo.definer = value;
                        break;
                    case 4:
                        foo.modified = r[j].get!(DateTime);
                        break;
                    case 5:
                        foo.created = r[j].get!(DateTime);
                        break;
                    case 6:
                        foo.securityType = value;
                        break;
                    case 7:
                        foo.comment = value;
                        break;
                    case 8:
                        foo.charSetClient = value;
                        break;
                    case 9:
                        foo.collationConnection = value;
                        break;
                    case 10:
                        foo.collationDB = value;
                        break;
                    default:
                        assert(0);
                }
            }
            pa[i] = foo;
        }
        return pa;
    }

public:
    this(Connection con)
    {
        _con = con;
    }

    /**
     * List the available databases
     *
     * Note that if you have connected using the credentials of a user with limited permissions
     * you may not get many results.
     *
     * Returns:
     *    An array of strings
     */
    string[] databases()
    {
        auto cmd = Command(_con, "SHOW DATABASES");
        auto rs = cmd.execSQLResult();
        string[] dbNames;
        dbNames.length = rs.length;
        foreach (size_t i; 0..rs.length)
            dbNames[i] = rs[i][0].toString();
        return dbNames;
    }

    /**
     * List the tables in the current database
     *
     * Returns:
     *    An array of strings
     */
    string[] tables()
    {
        auto cmd = Command(_con, "SHOW TABLES");
        auto rs = cmd.execSQLResult();
        string[] tblNames;
        tblNames.length = rs.length;
        foreach (size_t i; 0..rs.length)
            tblNames[i] = rs[i][0].toString();
        return tblNames;
    }

    /**
     * Get column metadata for a table in the current database
     *
     * Params:
     *    table = The table name
     * Returns:
     *    An array of ColumnInfo structs
     */
    ColumnInfo[] columns(string table)
    {
        string query = "SELECT * FROM information_schema.COLUMNS WHERE table_name='" ~ table ~ "'";
        auto cmd = Command(_con, query);
        auto rs = cmd.execSQLResult();
        ColumnInfo[] ca;
        ca.length = rs.length;
        foreach (size_t i; 0..rs.length)
        {
            ColumnInfo col;
            Row r = rs[i];
            for (int j = 1; j < 19; j++)
            {
                string t;
                bool isNull = r.isNull(j);
                if (!isNull)
                    t = to!string(r[j]);
                switch (j)
                {
                    case 1:
                        col.schema = t;
                        break;
                    case 2:
                        col.table = t;
                        break;
                    case 3:
                        col.name = t;
                        break;
                    case 4:
                        if(isNull)
                            col.index = -1;
                        else
                            col.index = cast(uint)(r[j].get!ulong() - 1);
                        //col.index = cast(uint)(r[j].get!(ulong)-1);
                        break;
                    case 5:
                        if (isNull)
                            col.defaultNull = true;
                        else
                            col.defaultValue = t;
                        break;
                    case 6:
                        if (t == "YES")
                        col.nullable = true;
                        break;
                    case 7:
                        col.type = t;
                        break;
                    case 8:
                        col.charsMax = cast(long)(isNull? -1L: r[j].get!(ulong));
                        break;
                    case 9:
                        col.octetsMax = cast(long)(isNull? -1L: r[j].get!(ulong));
                        break;
                    case 10:
                        col.numericPrecision = cast(short) (isNull? -1: r[j].get!(ulong));
                        break;
                    case 11:
                        col.numericScale = cast(short) (isNull? -1: r[j].get!(ulong));
                        break;
                    case 12:
                        col.charSet = isNull? "<NULL>": t;
                        break;
                    case 13:
                        col.collation = isNull? "<NULL>": t;
                        break;
                    case 14:
                        col.colType = t;
                        break;
                    case 15:
                        col.key = t;
                        break;
                    case 16:
                        col.extra = t;
                        break;
                    case 17:
                        col.privileges = t;
                        break;
                    case 18:
                        col.comment = t;
                        break;
                    default:
                        break;
                }
            }
            ca[i] = col;
        }
        return ca;
    }

    /**
     * Get list of stored functions in the current database, and their properties
     *
     */
    MySQLProcedure[] functions()
    {
        return stored(false);
    }

    /**
     * Get list of stored procedures in the current database, and their properties
     *
     */
    MySQLProcedure[] procedures()
    {
        return stored(true);
    }
}

/+
unittest
{
    auto c = new Connection("localhost", "user", "password", "mysqld");
    scope(exit) c.close();
    MetaData md = MetaData(c);
    string[] dbList = md.databases();
    int count = 0;
    foreach (string db; dbList)
    {
        if (db == "mysqld" || db == "information_schema")
            count++;
    }
    assert(count == 2);
    string[] tList = md.tables();
    count = 0;
    foreach (string t; tList)
    {
        if (t == "basetest" || t == "tblob")
            count++;
    }
    assert(count == 2);

    ColumnInfo[] ca = md.columns("basetest");
    assert(ca[0].schema == "mysqld" && ca[0].table == "basetest" && ca[0].name == "boolcol" && ca[0].index == 0 &&
           ca[0].defaultNull && ca[0].nullable && ca[0].type == "bit" && ca[0].charsMax == -1 && ca[0].octetsMax == -1 &&
           ca[0].numericPrecision == 1 && ca[0].numericScale == -1 && ca[0].charSet == "<NULL>" && ca[0].collation == "<NULL>"  &&
           ca[0].colType == "bit(1)");
    assert(ca[1].schema == "mysqld" && ca[1].table == "basetest" && ca[1].name == "bytecol" && ca[1].index == 1 &&
           ca[1].defaultNull && ca[1].nullable && ca[1].type == "tinyint" && ca[1].charsMax == -1 && ca[1].octetsMax == -1 &&
           ca[1].numericPrecision == 3 && ca[1].numericScale == 0 && ca[1].charSet == "<NULL>" && ca[1].collation == "<NULL>"  &&
           ca[1].colType == "tinyint(4)");
    assert(ca[2].schema == "mysqld" && ca[2].table == "basetest" && ca[2].name == "ubytecol" && ca[2].index == 2 &&
           ca[2].defaultNull && ca[2].nullable && ca[2].type == "tinyint" && ca[2].charsMax == -1 && ca[2].octetsMax == -1 &&
           ca[2].numericPrecision == 3 && ca[2].numericScale == 0 && ca[2].charSet == "<NULL>" && ca[2].collation == "<NULL>"  &&
           ca[2].colType == "tinyint(3) unsigned");
    assert(ca[3].schema == "mysqld" && ca[3].table == "basetest" && ca[3].name == "shortcol" && ca[3].index == 3 &&
           ca[3].defaultNull && ca[3].nullable && ca[3].type == "smallint" && ca[3].charsMax == -1 && ca[3].octetsMax == -1 &&
           ca[3].numericPrecision == 5 && ca[3].numericScale == 0 && ca[3].charSet == "<NULL>" && ca[3].collation == "<NULL>"  &&
           ca[3].colType == "smallint(6)");
    assert(ca[4].schema == "mysqld" && ca[4].table == "basetest" && ca[4].name == "ushortcol" && ca[4].index == 4 &&
           ca[4].defaultNull && ca[4].nullable && ca[4].type == "smallint" && ca[4].charsMax == -1 && ca[4].octetsMax == -1 &&
           ca[4].numericPrecision == 5 && ca[4].numericScale == 0 && ca[4].charSet == "<NULL>" && ca[4].collation == "<NULL>"  &&
           ca[4].colType == "smallint(5) unsigned");
    assert(ca[5].schema == "mysqld" && ca[5].table == "basetest" && ca[5].name == "intcol" && ca[5].index == 5 &&
           ca[5].defaultNull && ca[5].nullable && ca[5].type == "int" && ca[5].charsMax == -1 && ca[5].octetsMax == -1 &&
           ca[5].numericPrecision == 10 && ca[5].numericScale == 0 && ca[5].charSet == "<NULL>" && ca[5].collation == "<NULL>"  &&
           ca[5].colType == "int(11)");
    assert(ca[6].schema == "mysqld" && ca[6].table == "basetest" && ca[6].name == "uintcol" && ca[6].index == 6 &&
           ca[6].defaultNull && ca[6].nullable && ca[6].type == "int" && ca[6].charsMax == -1 && ca[6].octetsMax == -1 &&
           ca[6].numericPrecision == 10 && ca[6].numericScale == 0 && ca[6].charSet == "<NULL>" && ca[6].collation == "<NULL>"  &&
           ca[6].colType == "int(10) unsigned");
    assert(ca[7].schema == "mysqld" && ca[7].table == "basetest" && ca[7].name == "longcol" && ca[7].index == 7 &&
           ca[7].defaultNull && ca[7].nullable && ca[7].type == "bigint" && ca[7].charsMax == -1 && ca[7].octetsMax == -1 &&
           ca[7].numericPrecision == 19 && ca[7].numericScale == 0 && ca[7].charSet == "<NULL>" && ca[7].collation == "<NULL>"  &&
           ca[7].colType == "bigint(20)");
    assert(ca[8].schema == "mysqld" && ca[8].table == "basetest" && ca[8].name == "ulongcol" && ca[8].index == 8 &&
           ca[8].defaultNull && ca[8].nullable && ca[8].type == "bigint" && ca[8].charsMax == -1 && ca[8].octetsMax == -1 &&
           ca[8].numericPrecision == 20 && ca[8].numericScale == 0 && ca[8].charSet == "<NULL>" && ca[8].collation == "<NULL>"  &&
           ca[8].colType == "bigint(20) unsigned");
    assert(ca[9].schema == "mysqld" && ca[9].table == "basetest" && ca[9].name == "charscol" && ca[9].index == 9 &&
           ca[9].defaultNull && ca[9].nullable && ca[9].type == "char" && ca[9].charsMax == 10 && ca[9].octetsMax == 10 &&
           ca[9].numericPrecision == -1 && ca[9].numericScale == -1 && ca[9].charSet == "latin1" && ca[9].collation == "latin1_swedish_ci"  &&
           ca[9].colType == "char(10)");
    assert(ca[10].schema == "mysqld" && ca[10].table == "basetest" && ca[10].name == "stringcol" && ca[10].index == 10 &&
           ca[10].defaultNull && ca[10].nullable && ca[10].type == "varchar" && ca[10].charsMax == 50 && ca[10].octetsMax == 50 &&
           ca[10].numericPrecision == -1 && ca[10].numericScale == -1 && ca[10].charSet == "latin1" && ca[10].collation == "latin1_swedish_ci"  &&
           ca[10].colType == "varchar(50)");
    assert(ca[11].schema == "mysqld" && ca[11].table == "basetest" && ca[11].name == "bytescol" && ca[11].index == 11 &&
           ca[11].defaultNull && ca[11].nullable && ca[11].type == "tinyblob" && ca[11].charsMax == 255 && ca[11].octetsMax == 255 &&
           ca[11].numericPrecision == -1 && ca[11].numericScale == -1 && ca[11].charSet == "<NULL>" && ca[11].collation == "<NULL>"  &&
           ca[11].colType == "tinyblob");
    assert(ca[12].schema == "mysqld" && ca[12].table == "basetest" && ca[12].name == "datecol" && ca[12].index == 12 &&
           ca[12].defaultNull && ca[12].nullable && ca[12].type == "date" && ca[12].charsMax == -1 && ca[12].octetsMax == -1 &&
           ca[12].numericPrecision == -1 && ca[12].numericScale == -1 && ca[12].charSet == "<NULL>" && ca[12].collation == "<NULL>"  &&
           ca[12].colType == "date");
    assert(ca[13].schema == "mysqld" && ca[13].table == "basetest" && ca[13].name == "timecol" && ca[13].index == 13 &&
           ca[13].defaultNull && ca[13].nullable && ca[13].type == "time" && ca[13].charsMax == -1 && ca[13].octetsMax == -1 &&
           ca[13].numericPrecision == -1 && ca[13].numericScale == -1 && ca[13].charSet == "<NULL>" && ca[13].collation == "<NULL>"  &&
           ca[13].colType == "time");
    assert(ca[14].schema == "mysqld" && ca[14].table == "basetest" && ca[14].name == "dtcol" && ca[14].index == 14 &&
           ca[14].defaultNull && ca[14].nullable && ca[14].type == "datetime" && ca[14].charsMax == -1 && ca[14].octetsMax == -1 &&
           ca[14].numericPrecision == -1 && ca[14].numericScale == -1 && ca[14].charSet == "<NULL>" && ca[14].collation == "<NULL>"  &&
           ca[14].colType == "datetime");
    assert(ca[15].schema == "mysqld" && ca[15].table == "basetest" && ca[15].name == "doublecol" && ca[15].index == 15 &&
           ca[15].defaultNull && ca[15].nullable && ca[15].type == "double" && ca[15].charsMax == -1 && ca[15].octetsMax == -1 &&
           ca[15].numericPrecision == 22 && ca[15].numericScale == -1 && ca[15].charSet == "<NULL>" && ca[15].collation == "<NULL>"  &&
           ca[15].colType == "double");
    assert(ca[16].schema == "mysqld" && ca[16].table == "basetest" && ca[16].name == "floatcol" && ca[16].index == 16 &&
           ca[16].defaultNull && ca[16].nullable && ca[16].type == "float" && ca[16].charsMax == -1 && ca[16].octetsMax == -1 &&
           ca[16].numericPrecision == 12 && ca[16].numericScale == -1 && ca[16].charSet == "<NULL>" && ca[16].collation == "<NULL>"  &&
           ca[16].colType == "float");
    assert(ca[17].schema == "mysqld" && ca[17].table == "basetest" && ca[17].name == "nullcol" && ca[17].index == 17 &&
           ca[17].defaultNull && ca[17].nullable && ca[17].type == "int" && ca[17].charsMax == -1 && ca[17].octetsMax == -1 &&
           ca[17].numericPrecision == 10 && ca[17].numericScale == 0 && ca[17].charSet == "<NULL>" && ca[17].collation == "<NULL>"  &&
           ca[17].colType == "int(11)");
    MySQLProcedure[] pa = md.functions();
    assert(pa[0].db == "mysqld" && pa[0].name == "hello" && pa[0].type == "FUNCTION");
    pa = md.procedures();
    assert(pa[0].db == "mysqld" && pa[0].name == "insert2" && pa[0].type == "PROCEDURE");
}
+/
