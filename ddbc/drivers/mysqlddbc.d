module ddbc.drivers.mysqlddbc;

import std.algorithm;
import std.conv;
import std.exception;
import std.stdio;
import std.string;
import std.variant;
import ddbc.common;
import ddbc.core;
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
	MySQLStatement [] activeStatements;

	void closeUnclosedStatements() {
		MySQLStatement [] list = activeStatements.dup;
		foreach(stmt; list) {
			stmt.close();
		}
	}

	void checkClosed() {
		if (closed)
			throw new SQLException("Connection is already closed");
	}

public:

    ddbc.drivers.mysql.Connection getConnection() { return conn; }
	void onStatementClosed(MySQLStatement stmt) {
		foreach(index, item; activeStatements) {
			if (item == stmt) {
				remove(activeStatements, index);
				return;
			}
		}
	}

    this(string url, string[string] params) {
        this.url = url;
        this.params = params;
        //writeln("parsing url " ~ url);
        string urlParams;
        ptrdiff_t qmIndex = std.string.indexOf(url, '?');
        if (qmIndex >=0 ) {
            urlParams = url[qmIndex + 1 .. $];
            url = url[0 .. qmIndex];
            // TODO: parse params
        }
        string dbName = "";
		ptrdiff_t firstSlashes = std.string.indexOf(url, "//");
		ptrdiff_t lastSlash = std.string.lastIndexOf(url, '/');
		ptrdiff_t hostNameStart = firstSlashes >= 0 ? firstSlashes + 2 : 0;
		ptrdiff_t hostNameEnd = lastSlash >=0 && lastSlash > firstSlashes + 1 ? lastSlash : url.length;
        if (hostNameEnd < url.length - 1) {
            dbName = url[hostNameEnd + 1 .. $];
        }
        hostname = url[hostNameStart..hostNameEnd];
        if (hostname.length == 0)
            hostname = "localhost";
		ptrdiff_t portDelimiter = std.string.indexOf(hostname, ":");
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
		checkClosed();
		closeUnclosedStatements();
        conn.close();
        closed = true;
    }
    override void commit() {
        // TODO:
    }
    override Statement createStatement() {
		MySQLStatement stmt = new MySQLStatement(this);
		activeStatements ~= stmt;
        return stmt;
    }
    PreparedStatement prepareStatement(string sql) {
        MySQLPreparedStatement stmt = new MySQLPreparedStatement(this, sql);
        activeStatements ~= stmt;
        return stmt;
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
	MySQLResultSet resultSet;
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
		resultSet = new MySQLResultSet(this, rs);
        return resultSet;
    }
    override int executeUpdate(string query) {
		cmd = new Command(conn.getConnection(), query);
		ulong rowsAffected = 0;
		cmd.execSQL(rowsAffected);
        return cast(int)rowsAffected;
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
		if (resultSet !is null) {
			resultSet.onStatementClosed();
			resultSet = null;
		}
    }
}

class MySQLPreparedStatement : MySQLStatement, PreparedStatement {
    string query;
    int paramCount;
    this(MySQLConnection conn, string query) {
        super(conn);
        this.query = query;
        cmd = new Command(conn.getConnection(), query);
        cmd.prepare();
        paramCount = cmd.getParamCount();
    }
    void checkIndex(int index) {
        if (index < 1 || index > paramCount)
            throw new SQLException("Parameter index " ~ to!string(index) ~ " is out of range");
    }
    ref Variant getParam(int index) {
        checkIndex(index);
        return cmd.param(cast(ushort)(index - 1));
    }
public:
    override int executeUpdate() {
        ulong rowsAffected = 0;
        cmd.execPrepared(rowsAffected);
        return cast(int)rowsAffected;
    }
    override ddbc.core.ResultSet executeQuery() {
        rs = cmd.execPreparedResult();
        resultSet = new MySQLResultSet(this, rs);
        return resultSet;
    }
    
    override void clearParameters() {
        for (int i = 1; i <= paramCount; i++)
            setNull(i);
    }
    
    override void setBoolean(int parameterIndex, bool x) {
        checkIndex(parameterIndex);
        cmd.param(parameterIndex-1) = x;
    }
    override void setLong(int parameterIndex, long x) {
        checkIndex(parameterIndex);
        cmd.param(parameterIndex-1) = x;
    }
    override void setUlong(int parameterIndex, ulong x) {
        checkIndex(parameterIndex);
        cmd.param(parameterIndex-1) = x;
    }
    override void setInt(int parameterIndex, int x) {
        checkIndex(parameterIndex);
        cmd.param(parameterIndex-1) = x;
    }
    override void setUint(int parameterIndex, uint x) {
        checkIndex(parameterIndex);
        cmd.param(parameterIndex-1) = x;
    }
    override void setShort(int parameterIndex, short x) {
        checkIndex(parameterIndex);
        cmd.param(parameterIndex-1) = x;
    }
    override void setUshort(int parameterIndex, ushort x) {
        checkIndex(parameterIndex);
        cmd.param(parameterIndex-1) = x;
    }
    override void setByte(int parameterIndex, byte x) {
        checkIndex(parameterIndex);
        cmd.param(parameterIndex-1) = x;
    }
    override void setUbyte(int parameterIndex, ubyte x) {
        checkIndex(parameterIndex);
        cmd.param(parameterIndex-1) = x;
    }
    override void setBytes(int parameterIndex, byte[] x) {
        checkIndex(parameterIndex);
        if (x == null)
            setNull(parameterIndex);
        else
            cmd.param(parameterIndex-1) = x;
    }
    override void setUbytes(int parameterIndex, ubyte[] x) {
        checkIndex(parameterIndex);
        if (x == null)
            setNull(parameterIndex);
        else
            cmd.param(parameterIndex-1) = x;
    }
    override void setString(int parameterIndex, string x) {
        checkIndex(parameterIndex);
        if (x == null)
            setNull(parameterIndex);
        else
            cmd.param(parameterIndex-1) = x;
    }
    override void setNull(int parameterIndex) {
        checkIndex(parameterIndex);
        cmd.setNullParam(parameterIndex-1);
    }
    override void setNull(int parameterIndex, int sqlType) {
        setNull(parameterIndex);
    }
}

class MySQLResultSet : ResultSetImpl {
    private MySQLStatement stmt;
    private ddbc.drivers.mysql.ResultSet rs;
    private bool closed;
    private int currentRowIndex;
    private int rowCount;
    private int[string] columnMap;
    private bool lastIsNull;
    private int columnCount;

    Variant getValue(int columnIndex) {
		checkClosed();
        enforceEx!SQLException(columnIndex >= 1 && columnIndex <= columnCount, "Column index out of bounds: " ~ to!string(columnIndex));
        enforceEx!SQLException(currentRowIndex >= 0 && currentRowIndex < rowCount, "No current row in result set");
        lastIsNull = rs[currentRowIndex].isNull(columnIndex - 1);
		Variant res;
		if (!lastIsNull)
		    res = rs[currentRowIndex][columnIndex - 1];
        return res;
    }

	void checkClosed() {
		if (closed)
			throw new SQLException("Result set is already closed");
	}

public:
    this(MySQLStatement stmt, ddbc.drivers.mysql.ResultSet resultSet) {
        this.stmt = stmt;
        this.rs = resultSet;
        closed = false;
        rowCount = rs.length;
        currentRowIndex = -1;
        columnMap = rs.getColNameMap();
        columnCount = rs.getColNames().length;
    }

	void onStatementClosed() {
		closed = true;
	}
    string decodeTextBlob(ubyte[] data) {
        char[] res = new char[data.length];
        foreach (i, ch; data) {
            res[i] = cast(char)ch;
        }
        return to!string(res);
    }

    // ResultSet interface implementation

    override void close() {
        checkClosed();
       	stmt.closeResultSet();
       	closed = true;
    }
    override bool first() {
		checkClosed();
        currentRowIndex = 0;
        return currentRowIndex >= 0 && currentRowIndex < rowCount;
    }
    override bool isFirst() {
		checkClosed();
		return rowCount > 0 && currentRowIndex == 0;
    }
    override bool isLast() {
		checkClosed();
		return rowCount > 0 && currentRowIndex == rowCount - 1;
    }
    override bool next() {
		checkClosed();
		if (currentRowIndex + 1 >= rowCount)
            return false;
        currentRowIndex++;
        return true;
    }
    
    override int findColumn(string columnName) {
		checkClosed();
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
    override ubyte getUbyte(int columnIndex) {
        Variant v = getValue(columnIndex);
        if (lastIsNull)
            return 0;
        if (v.convertsTo!(ubyte))
            return v.get!(ubyte);
        if (v.convertsTo!(long))
            return to!ubyte(v.get!(long));
        throw new SQLException("Cannot convert field " ~ to!string(columnIndex) ~ " to ubyte");
    }
    override byte getByte(int columnIndex) {
        Variant v = getValue(columnIndex);
        if (lastIsNull)
            return 0;
        if (v.convertsTo!(byte))
            return v.get!(byte);
        if (v.convertsTo!(long))
            return to!byte(v.get!(long));
        throw new SQLException("Cannot convert field " ~ to!string(columnIndex) ~ " to byte");
    }
    override short getShort(int columnIndex) {
        Variant v = getValue(columnIndex);
        if (lastIsNull)
            return 0;
        if (v.convertsTo!(short))
            return v.get!(short);
        if (v.convertsTo!(long))
            return to!short(v.get!(long));
        throw new SQLException("Cannot convert field " ~ to!string(columnIndex) ~ " to short");
    }
    override ushort getUshort(int columnIndex) {
        Variant v = getValue(columnIndex);
        if (lastIsNull)
            return 0;
        if (v.convertsTo!(ushort))
            return v.get!(ushort);
        if (v.convertsTo!(long))
            return to!ushort(v.get!(long));
        throw new SQLException("Cannot convert field " ~ to!string(columnIndex) ~ " to ushort");
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
    override uint getUint(int columnIndex) {
        Variant v = getValue(columnIndex);
        if (lastIsNull)
            return 0;
        if (v.convertsTo!(uint))
            return v.get!(uint);
        if (v.convertsTo!(ulong))
            return to!int(v.get!(ulong));
        throw new SQLException("Cannot convert field " ~ to!string(columnIndex) ~ " to uint");
    }
    override long getLong(int columnIndex) {
        Variant v = getValue(columnIndex);
        if (lastIsNull)
            return 0;
        if (v.convertsTo!(long))
            return v.get!(long);
        throw new SQLException("Cannot convert field " ~ to!string(columnIndex) ~ " to long");
    }
    override ulong getUlong(int columnIndex) {
        Variant v = getValue(columnIndex);
        if (lastIsNull)
            return 0;
        if (v.convertsTo!(ulong))
            return v.get!(ulong);
        throw new SQLException("Cannot convert field " ~ to!string(columnIndex) ~ " to ulong");
    }
    override double getDouble(int columnIndex) {
        Variant v = getValue(columnIndex);
        if (lastIsNull)
            return 0;
        if (v.convertsTo!(double))
            return v.get!(double);
        throw new SQLException("Cannot convert field " ~ to!string(columnIndex) ~ " to double");
    }
    override float getFloat(int columnIndex) {
        Variant v = getValue(columnIndex);
        if (lastIsNull)
            return 0;
        if (v.convertsTo!(float))
            return v.get!(float);
        throw new SQLException("Cannot convert field " ~ to!string(columnIndex) ~ " to float");
    }
    override ubyte[] getBytes(int columnIndex) {
        Variant v = getValue(columnIndex);
        if (lastIsNull)
            return null;
        if (v.convertsTo!(ubyte[])) {
            return v.get!(ubyte[]);
        }
        throw new SQLException("Cannot convert field " ~ to!string(columnIndex) ~ " to ubyte[]");
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
    override bool wasNull() {
		checkClosed();
		return lastIsNull;
    }
    override bool isNull(int columnIndex) {
        checkClosed();
        enforceEx!SQLException(columnIndex >= 1 && columnIndex <= columnCount, "Column index out of bounds: " ~ to!string(columnIndex));
        enforceEx!SQLException(currentRowIndex >= 0 && currentRowIndex < rowCount, "No current row in result set");
        return rs[currentRowIndex].isNull(columnIndex - 1);
    }

    //Retrieves the Statement object that produced this ResultSet object.
    override Statement getStatement() {
        return stmt;
    }

    //Retrieves the current row number
    override int getRow() {
        checkClosed();
        if (currentRowIndex <0 || currentRowIndex >= rowCount)
            return 0;
        return currentRowIndex + 1;
    }

    //Retrieves the fetch size for this ResultSet object.
    override int getFetchSize() {
        checkClosed();
        return rowCount;
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
