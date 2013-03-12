module ddbc.drivers.mysqlddbc;

import std.string;
import std.conv;
import std.stdio;
import std.variant;
import ddbc.core;
import ddbc.common;
import ddbc.drivers.mysql;

class MySQLConnection : ddbc.core.Connection {
private:
    string url;
    string[string] params;
    string dbName;
    string username;
    string password;
    string hostname;
    int port = 3306;
    ddbc.drivers.mysql.Connection conn;
    bool closed;
public:

    ddbc.drivers.mysql.Connection getConnection() { return conn; }

    this(string url, string[string] params) {
        this.url = url;
        this.params = params;
        //writeln("parsing url " ~ url);
        string urlParams;
        auto qmIndex = indexOf(url, '?');
        if (qmIndex >=0 ) {
            urlParams = url[qmIndex + 1 .. $];
            url = url[0 .. qmIndex];
            // TODO: parse params
        }
        string dbName = "";
		auto firstSlashes = indexOf(url, "//");
		auto lastSlash = lastIndexOf(url, '/');
		auto hostNameStart = firstSlashes >= 0 ? firstSlashes + 2 : 0;
		auto hostNameEnd = lastSlash >=0 && lastSlash > firstSlashes + 1 ? lastSlash : url.length;
        if (hostNameEnd < url.length - 1) {
            dbName = url[hostNameEnd + 1 .. $];
        }
        hostname = url[hostNameStart..hostNameEnd];
        if (hostname.length == 0)
            hostname = "localhost";
		auto portDelimiter = indexOf(hostname, ":");
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

        conn = new ddbc.drivers.mysql.Connection(hostname, username, password, dbName, cast(ushort)port);
    }
    override void close() {
        conn.close();
        closed = true;
    }
    override void commit() {
        // TODO:
    }
    override Statement createStatement() {
        return new MySQLStatement(this);
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

class MySQLStatement : Statement {

    private MySQLConnection conn;
    private Command * cmd;
    ddbc.drivers.mysql.ResultSet rs;
    this(MySQLConnection conn) {
        this.conn = conn;
    }

public:
    MySQLConnection getConnection() {
        return conn;
    }
    override ddbc.core.ResultSet executeQuery(string query) {
        cmd = new Command(conn.getConnection(), query);
        rs = cmd.execSQLResult();
        return new MySQLResultSet(this, rs);
    }
    override int executeUpdate(string query) {
        return false;
    }
    override void close() {
        closeResultSet();
    }
    void closeResultSet() {
        if (cmd == null) {
            return;
        }
        cmd.releaseStatement();
        delete cmd;
        cmd = null;
    }
}

class MySQLResultSet : ddbc.core.ResultSet {
    private MySQLStatement stmt;
    private ddbc.drivers.mysql.ResultSet rs;
    private bool closed;
    private int currentRowIndex;
    private int rowCount;
    private int[string] columnMap;
    private bool lastIsNull;
    private int columnCount;

    Variant getValue(int columnIndex) {
        if (columnIndex < 1 || columnIndex > columnCount)
            throw new SQLException("Column index out of bounds: " ~ to!string(columnIndex));
        if (currentRowIndex < 0 || currentRowIndex >= rowCount)
            throw new SQLException("No current row in result set");
		lastIsNull = rs[currentRowIndex].isNull(columnIndex - 1);
		Variant res;
		if (!lastIsNull)
		    res = rs[currentRowIndex][columnIndex - 1];
        return res;
    }

public:
    this(MySQLStatement stmt, ddbc.drivers.mysql.ResultSet resultSet) {
        this.stmt = stmt;
        this.rs = resultSet;
        closed = false;
        rowCount = cast(int)rs.length;
        currentRowIndex = -1;
        columnMap = rs.getColNameMap();
        columnCount = cast(int)rs.getColNames().length;
    }

    override void close() {
        stmt.closeResultSet();
        closed = true;
    }
    override bool first() {
        currentRowIndex = 0;
        return currentRowIndex >= 0 && currentRowIndex < rowCount;
    }
    override bool isFirst() {
        return rowCount > 0 && currentRowIndex == 0;
    }
    override bool isLast() {
        return rowCount > 0 && currentRowIndex == rowCount - 1;
    }
    override bool next() {
        if (currentRowIndex + 1 >= rowCount)
            return false;
        currentRowIndex++;
        return true;
    }
    
    override int findColumn(string columnName) {
        int * p = (columnName in columnMap);
        if (!p)
            throw new SQLException("Column " ~ columnName ~ " not found");
        return *p + 1;
    }
    override bool getBoolean(int columnIndex) {
        Variant v = getValue(columnIndex);
        if (lastIsNull)
            return false;
        if (v.convertsTo!(bool))
            return v.get!(bool);
        if (v.convertsTo!(int))
            return v.get!(int) != 0;
        if (v.convertsTo!(long))
            return v.get!(long) != 0;
        throw new SQLException("Cannot convert field " ~ to!string(columnIndex) ~ " to boolean");
    }
    override bool getBoolean(string columnName) {
        return getBoolean(findColumn(columnName));
    }
    override int getInt(int columnIndex) {
        Variant v = getValue(columnIndex);
        if (lastIsNull)
            return 0;
        if (v.convertsTo!(int))
            return v.get!(int);
        if (v.convertsTo!(long))
            return to!int(v.get!(long));
        throw new SQLException("Cannot convert field " ~ to!string(columnIndex) ~ " to int");
    }
    override int getInt(string columnName) {
        return getInt(findColumn(columnName));
    }
    override long getLong(int columnIndex) {
        Variant v = getValue(columnIndex);
        if (lastIsNull)
            return 0;
        if (v.convertsTo!(long))
            return v.get!(long);
        throw new SQLException("Cannot convert field " ~ to!string(columnIndex) ~ " to long");
    }
    override long getLong(string columnName) {
        return getLong(findColumn(columnName));
    }
	string decodeTextBlob(ubyte[] data) {
		char[] res = new char[data.length];
		foreach (i, ch; data) {
			res[i] = cast(char)ch;
		}
		return to!string(res);
	}
    override string getString(int columnIndex) {
        Variant v = getValue(columnIndex);
        if (lastIsNull)
            return null;
		if (v.convertsTo!(ubyte[])) {
			// assume blob encoding is utf-8
			// TODO: check field encoding
			return decodeTextBlob(v.get!(ubyte[]));
		}
		return v.toString();
    }
    override string getString(string columnName) {
        return getString(findColumn(columnName));
    }
    override bool wasNull() {
        return lastIsNull;
    }
}

// sample URL:
// mysql://localhost:3306/DatabaseName
class MySQLDriver : Driver {
    // helper function
    public static string generateUrl(string host, ushort port, string dbname) {
        return "mysql://" ~ host ~ ":" ~ to!string(port) ~ "/" ~ dbname;
    }
    public static setUserAndPassword(ref string[string] params, string username, string password) {
        params["user"] = username;
        params["password"] = password;
    }
    override ddbc.core.Connection connect(string url, string[string] params) {
        //writeln("MySQLDriver.connect " ~ url);
        return new MySQLConnection(url, params);
    }
}
