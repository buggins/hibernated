module ddbc.drivers.mysqlddbc;

import std.string;
import std.conv;
import std.stdio;
import ddbc.core;
import ddbc.common;
import ddbc.drivers.mysql;

class MySQLConnection : Connection {
private:
    string url;
    string[string] params;
    string dbName;
    string username;
    string password;
    string hostname;
    int port = 3306;
    MySQLNConnection conn;
    bool closed;
public:
    this(string url, string[string] params) {
        this.url = url;
        this.params = params;
        //writeln("parsing url " ~ url);
        string urlParams;
        int qmIndex = indexOf(url, '?');
        if (qmIndex >=0 ) {
            urlParams = url[qmIndex + 1 .. $];
            url = url[0 .. qmIndex];
            // TODO: parse params
        }
        string dbName = "";
        int firstSlashes = indexOf(url, "//");
        int lastSlash = lastIndexOf(url, '/');
        int hostNameStart = firstSlashes >= 0 ? firstSlashes + 2 : 0;
        int hostNameEnd = lastSlash >=0 && lastSlash > firstSlashes + 1 ? lastSlash : url.length;
        if (hostNameEnd < url.length - 1) {
            dbName = url[hostNameEnd + 1 .. $];
        }
        hostname = url[hostNameStart..hostNameEnd];
        if (hostname.length == 0)
            hostname = "localhost";
        int portDelimiter = indexOf(hostname, ":");
        if (portDelimiter >= 0) {
            string portString = hostname[portDelimiter + 1 .. $];
            hostname = hostname[0 .. portDelimiter];
            if (portString.length > 0)
                port = to!int(portString);
            if (port < 1 || port > 65535)
                port = 3306;
        }
        username = params["user"];
        password = params["password"];

        //writeln("host " ~ hostname ~ " : " ~ to!string(port) ~ " db=" ~ dbName ~ " user=" ~ username ~ " pass=" ~ password);

        conn = new MySQLNConnection(hostname, username, password, dbName, cast(ushort)port);
    }
    override void close() {
        conn.close();
        closed = true;
    }
    override void commit() {
        // TODO:
    }
    override Statement createStatement() {
        // TODO:
        return null;
    }
    override string getCatalog() {
        // TODO:
        return "";
    }
    override bool isClosed() {
        return closed;
    }
    override void rollback() {
        // TODO:
    }
    override bool getAutoCommit() {
        // TODO:
        return true;
    }
    override void setAutoCommit(bool autoCommit) {
        // TODO:
    }
}
// sample URL:
// mysql://localhost:3306/DatabaseName
class MySQLDriver : Driver {
    override Connection connect(string url, string[string] params) {
        //writeln("MySQLDriver.connect " ~ url);
        return new MySQLConnection(url, params);
    }
}
