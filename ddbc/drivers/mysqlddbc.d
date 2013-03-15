module ddbc.drivers.mysqlddbc;

import std.algorithm;
import std.conv;
import std.exception;
import std.stdio;
import std.string;
import std.variant;
import core.sync.mutex;
import ddbc.common;
import ddbc.core;
import ddbc.drivers.mysql;

version(unittest) {
    /*
        To allow unit tests using MySQL server,
        run mysql client using admin privileges, e.g. for MySQL server on localhost:
        > mysql -uroot

        Create test user and test DB:
        mysql> GRANT ALL PRIVILEGES ON *.* TO testuser@'%' IDENTIFIED BY 'testpassword';
        mysql> GRANT ALL PRIVILEGES ON *.* TO testuser@'localhost' IDENTIFIED BY 'testpassword';
        mysql> CREATE DATABASE testdb;
     */
    /// change to false to disable tests on real MySQL server
    immutable bool MYSQL_TESTS_ENABLED = true;
    /// change parameters if necessary
    const string MYSQL_UNITTEST_HOST = "localhost";
    const int    MYSQL_UNITTEST_PORT = 3306;
    const string MYSQL_UNITTEST_USER = "testuser";
    const string MYSQL_UNITTEST_PASSWORD = "testpassword";
    const string MYSQL_UNITTEST_DB = "testdb";

    static if (MYSQL_TESTS_ENABLED) {
        /// use this data source for tests
        DataSource createUnitTestMySQLDataSource() {
            MySQLDriver driver = new MySQLDriver();
            string url = MySQLDriver.generateUrl(MYSQL_UNITTEST_HOST, MYSQL_UNITTEST_PORT, MYSQL_UNITTEST_DB);
            string[string] params = MySQLDriver.setUserAndPassword(MYSQL_UNITTEST_USER, MYSQL_UNITTEST_PASSWORD);
            return new ConnectionPoolDataSourceImpl(driver, url, params);
        }
    }
}

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
    bool autocommit;
    Mutex mutex;


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

    void lock() {
        mutex.lock();
    }

    void unlock() {
        mutex.unlock();
    }

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
        mutex = new Mutex();
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
        closed = false;
        setAutoCommit(true);
    }
    override void close() {
		checkClosed();

        lock();
        scope(exit) unlock();

        closeUnclosedStatements();

        conn.close();
        closed = true;
    }
    override void commit() {
        checkClosed();

        lock();
        scope(exit) unlock();

        Statement stmt = createStatement();
        scope(exit) stmt.close();
        stmt.executeUpdate("COMMIT");
    }
    override Statement createStatement() {
        checkClosed();

        lock();
        scope(exit) unlock();

        MySQLStatement stmt = new MySQLStatement(this);
		activeStatements ~= stmt;
        return stmt;
    }

    PreparedStatement prepareStatement(string sql) {
        checkClosed();

        lock();
        scope(exit) unlock();

        MySQLPreparedStatement stmt = new MySQLPreparedStatement(this, sql);
        activeStatements ~= stmt;
        return stmt;
    }

    override string getCatalog() {
        return dbName;
    }

    /// Sets the given catalog name in order to select a subspace of this Connection object's database in which to work.
    override void setCatalog(string catalog) {
        checkClosed();
        if (dbName == catalog)
            return;

        lock();
        scope(exit) unlock();

        conn.selectDB(catalog);
        dbName = catalog;
    }

    override bool isClosed() {
        return closed;
    }

    override void rollback() {
        checkClosed();

        lock();
        scope(exit) unlock();

        Statement stmt = createStatement();
        scope(exit) stmt.close();
        stmt.executeUpdate("ROLLBACK");
    }
    override bool getAutoCommit() {
        return autocommit;
    }
    override void setAutoCommit(bool autoCommit) {
        checkClosed();
        if (this.autocommit == autoCommit)
            return;
        lock();
        scope(exit) unlock();

        Statement stmt = createStatement();
        scope(exit) stmt.close();
        stmt.executeUpdate("SET autocommit=" ~ (autoCommit ? "1" : "0"));
        this.autocommit = autoCommit;
    }
}

class MySQLStatement : Statement {
private:
    MySQLConnection conn;
    Command * cmd;
    ddbc.drivers.mysql.ResultSet rs;
	MySQLResultSet resultSet;

    bool closed;

public:
    void checkClosed() {
        enforceEx!SQLException(!closed, "Statement is already closed");
    }

    void lock() {
        conn.lock();
    }
    
    void unlock() {
        conn.unlock();
    }

    this(MySQLConnection conn) {
        this.conn = conn;
    }

    ResultSetMetaData createMetadata(FieldDescription[] fields) {
        ColumnMetadataItem[] res = new ColumnMetadataItem[fields.length];
        foreach(i, field; fields) {
            ColumnMetadataItem item = new ColumnMetadataItem();
            item.schemaName = field.db;
            item.name = field.originalName;
            item.label = field.name;
            item.precision = field.length;
            item.scale = field.scale;
            item.isNullable = !field.notNull;
            item.isSigned = !field.unsigned;
            // TODO: fill more params
            res[i] = item;
        }
        return new ResultSetMetaDataImpl(res);
    }
    ParameterMetaData createMetadata(ParamDescription[] fields) {
        ParameterMetaDataItem[] res = new ParameterMetaDataItem[fields.length];
        foreach(i, field; fields) {
            ParameterMetaDataItem item = new ParameterMetaDataItem();
            item.precision = field.length;
            item.scale = field.scale;
            item.isNullable = !field.notNull;
            item.isSigned = !field.unsigned;
            // TODO: fill more params
            res[i] = item;
        }
        return new ParameterMetaDataImpl(res);
    }
public:
    MySQLConnection getConnection() {
        checkClosed();
        return conn;
    }
    override ddbc.core.ResultSet executeQuery(string query) {
        checkClosed();
        lock();
        scope(exit) unlock();
        cmd = new Command(conn.getConnection(), query);
        rs = cmd.execSQLResult();
        resultSet = new MySQLResultSet(this, rs, createMetadata(cmd.getResultHeaders().getFieldDescriptions()));
        return resultSet;
    }
    override int executeUpdate(string query) {
        checkClosed();
        lock();
        scope(exit) unlock();
        cmd = new Command(conn.getConnection(), query);
		ulong rowsAffected = 0;
		cmd.execSQL(rowsAffected);
        return cast(int)rowsAffected;
    }
    override void close() {
        checkClosed();
        lock();
        scope(exit) unlock();
        closeResultSet();
        closed = true;
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
    ResultSetMetaData metadata;
    ParameterMetaData paramMetadata;
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

    /// Retrieves a ResultSetMetaData object that contains information about the columns of the ResultSet object that will be returned when this PreparedStatement object is executed.
    override ResultSetMetaData getMetaData() {
        checkClosed();
        lock();
        scope(exit) unlock();
        if (metadata is null)
            metadata = createMetadata(cmd.getPreparedHeaders().getFieldDescriptions());
        return metadata;
    }

    /// Retrieves the number, types and properties of this PreparedStatement object's parameters.
    override ParameterMetaData getParameterMetaData() {
        checkClosed();
        lock();
        scope(exit) unlock();
        if (paramMetadata is null)
            paramMetadata = createMetadata(cmd.getPreparedHeaders().getParamDescriptions());
        return paramMetadata;
    }

    override int executeUpdate() {
        checkClosed();
        lock();
        scope(exit) unlock();
        ulong rowsAffected = 0;
        cmd.execPrepared(rowsAffected);
        return cast(int)rowsAffected;
    }
    override ddbc.core.ResultSet executeQuery() {
        checkClosed();
        lock();
        scope(exit) unlock();
        rs = cmd.execPreparedResult();
        resultSet = new MySQLResultSet(this, rs, getMetaData());
        return resultSet;
    }
    
    override void clearParameters() {
        checkClosed();
        lock();
        scope(exit) unlock();
        for (int i = 1; i <= paramCount; i++)
            setNull(i);
    }
    
    override void setBoolean(int parameterIndex, bool x) {
        checkClosed();
        lock();
        scope(exit) unlock();
        checkIndex(parameterIndex);
        cmd.param(parameterIndex-1) = x;
    }
    override void setLong(int parameterIndex, long x) {
        checkClosed();
        lock();
        scope(exit) unlock();
        checkIndex(parameterIndex);
        cmd.param(parameterIndex-1) = x;
    }
    override void setUlong(int parameterIndex, ulong x) {
        checkClosed();
        lock();
        scope(exit) unlock();
        checkIndex(parameterIndex);
        cmd.param(parameterIndex-1) = x;
    }
    override void setInt(int parameterIndex, int x) {
        checkClosed();
        lock();
        scope(exit) unlock();
        checkIndex(parameterIndex);
        cmd.param(parameterIndex-1) = x;
    }
    override void setUint(int parameterIndex, uint x) {
        checkClosed();
        lock();
        scope(exit) unlock();
        checkIndex(parameterIndex);
        cmd.param(parameterIndex-1) = x;
    }
    override void setShort(int parameterIndex, short x) {
        checkClosed();
        lock();
        scope(exit) unlock();
        checkIndex(parameterIndex);
        cmd.param(parameterIndex-1) = x;
    }
    override void setUshort(int parameterIndex, ushort x) {
        checkClosed();
        lock();
        scope(exit) unlock();
        checkIndex(parameterIndex);
        cmd.param(parameterIndex-1) = x;
    }
    override void setByte(int parameterIndex, byte x) {
        checkClosed();
        lock();
        scope(exit) unlock();
        checkIndex(parameterIndex);
        cmd.param(parameterIndex-1) = x;
    }
    override void setUbyte(int parameterIndex, ubyte x) {
        checkClosed();
        lock();
        scope(exit) unlock();
        checkIndex(parameterIndex);
        cmd.param(parameterIndex-1) = x;
    }
    override void setBytes(int parameterIndex, byte[] x) {
        checkClosed();
        lock();
        scope(exit) unlock();
        checkIndex(parameterIndex);
        if (x == null)
            setNull(parameterIndex);
        else
            cmd.param(parameterIndex-1) = x;
    }
    override void setUbytes(int parameterIndex, ubyte[] x) {
        checkClosed();
        lock();
        scope(exit) unlock();
        checkIndex(parameterIndex);
        if (x == null)
            setNull(parameterIndex);
        else
            cmd.param(parameterIndex-1) = x;
    }
    override void setString(int parameterIndex, string x) {
        checkClosed();
        lock();
        scope(exit) unlock();
        checkIndex(parameterIndex);
        if (x == null)
            setNull(parameterIndex);
        else
            cmd.param(parameterIndex-1) = x;
    }
    override void setVariant(int parameterIndex, Variant x) {
        checkClosed();
        lock();
        scope(exit) unlock();
        checkIndex(parameterIndex);
        if (x == null)
            setNull(parameterIndex);
        else
            cmd.param(parameterIndex-1) = x;
    }
    override void setNull(int parameterIndex) {
        checkClosed();
        lock();
        scope(exit) unlock();
        checkIndex(parameterIndex);
        cmd.setNullParam(parameterIndex-1);
    }
    override void setNull(int parameterIndex, int sqlType) {
        checkClosed();
        lock();
        scope(exit) unlock();
        setNull(parameterIndex);
    }
}

class MySQLResultSet : ResultSetImpl {
    private MySQLStatement stmt;
    private ddbc.drivers.mysql.ResultSet rs;
    ResultSetMetaData metadata;
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

    void lock() {
        stmt.lock();
    }

    void unlock() {
        stmt.unlock();
    }

    this(MySQLStatement stmt, ddbc.drivers.mysql.ResultSet resultSet, ResultSetMetaData metadata) {
        this.stmt = stmt;
        this.rs = resultSet;
        this.metadata = metadata;
        closed = false;
        rowCount = cast(int)rs.length;
        currentRowIndex = -1;
        columnMap = rs.getColNameMap();
		columnCount = cast(int)rs.getColNames().length;
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

    //Retrieves the number, types and properties of this ResultSet object's columns
    override ResultSetMetaData getMetaData() {
        checkClosed();
        lock();
        scope(exit) unlock();
        return metadata;
    }

    override void close() {
        checkClosed();
        lock();
        scope(exit) unlock();
        stmt.closeResultSet();
       	closed = true;
    }
    override bool first() {
		checkClosed();
        lock();
        scope(exit) unlock();
        currentRowIndex = 0;
        return currentRowIndex >= 0 && currentRowIndex < rowCount;
    }
    override bool isFirst() {
		checkClosed();
        lock();
        scope(exit) unlock();
        return rowCount > 0 && currentRowIndex == 0;
    }
    override bool isLast() {
		checkClosed();
        lock();
        scope(exit) unlock();
        return rowCount > 0 && currentRowIndex == rowCount - 1;
    }
    override bool next() {
		checkClosed();
        lock();
        scope(exit) unlock();
        if (currentRowIndex + 1 >= rowCount)
            return false;
        currentRowIndex++;
        return true;
    }
    
    override int findColumn(string columnName) {
		checkClosed();
        lock();
        scope(exit) unlock();
        int * p = (columnName in columnMap);
        if (!p)
            throw new SQLException("Column " ~ columnName ~ " not found");
        return *p + 1;
    }

    override bool getBoolean(int columnIndex) {
        checkClosed();
        lock();
        scope(exit) unlock();
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
        checkClosed();
        lock();
        scope(exit) unlock();
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
        checkClosed();
        lock();
        scope(exit) unlock();
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
        checkClosed();
        lock();
        scope(exit) unlock();
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
        checkClosed();
        lock();
        scope(exit) unlock();
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
        checkClosed();
        lock();
        scope(exit) unlock();
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
        checkClosed();
        lock();
        scope(exit) unlock();
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
        checkClosed();
        lock();
        scope(exit) unlock();
        Variant v = getValue(columnIndex);
        if (lastIsNull)
            return 0;
        if (v.convertsTo!(long))
            return v.get!(long);
        throw new SQLException("Cannot convert field " ~ to!string(columnIndex) ~ " to long");
    }
    override ulong getUlong(int columnIndex) {
        checkClosed();
        lock();
        scope(exit) unlock();
        Variant v = getValue(columnIndex);
        if (lastIsNull)
            return 0;
        if (v.convertsTo!(ulong))
            return v.get!(ulong);
        throw new SQLException("Cannot convert field " ~ to!string(columnIndex) ~ " to ulong");
    }
    override double getDouble(int columnIndex) {
        checkClosed();
        lock();
        scope(exit) unlock();
        Variant v = getValue(columnIndex);
        if (lastIsNull)
            return 0;
        if (v.convertsTo!(double))
            return v.get!(double);
        throw new SQLException("Cannot convert field " ~ to!string(columnIndex) ~ " to double");
    }
    override float getFloat(int columnIndex) {
        checkClosed();
        lock();
        scope(exit) unlock();
        Variant v = getValue(columnIndex);
        if (lastIsNull)
            return 0;
        if (v.convertsTo!(float))
            return v.get!(float);
        throw new SQLException("Cannot convert field " ~ to!string(columnIndex) ~ " to float");
    }
    override ubyte[] getBytes(int columnIndex) {
        checkClosed();
        lock();
        scope(exit) unlock();
        Variant v = getValue(columnIndex);
        if (lastIsNull)
            return null;
        if (v.convertsTo!(ubyte[])) {
            return v.get!(ubyte[]);
        }
        throw new SQLException("Cannot convert field " ~ to!string(columnIndex) ~ " to ubyte[]");
    }
    override string getString(int columnIndex) {
        checkClosed();
        lock();
        scope(exit) unlock();
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
    override Variant getVariant(int columnIndex) {
        checkClosed();
        lock();
        scope(exit) unlock();
        Variant v = getValue(columnIndex);
        if (lastIsNull) {
            Variant vnull = null;
            return vnull;
        }
        return v;
    }
    override bool wasNull() {
        checkClosed();
        lock();
        scope(exit) unlock();
        return lastIsNull;
    }
    override bool isNull(int columnIndex) {
        checkClosed();
        lock();
        scope(exit) unlock();
        enforceEx!SQLException(columnIndex >= 1 && columnIndex <= columnCount, "Column index out of bounds: " ~ to!string(columnIndex));
        enforceEx!SQLException(currentRowIndex >= 0 && currentRowIndex < rowCount, "No current row in result set");
        return rs[currentRowIndex].isNull(columnIndex - 1);
    }

    //Retrieves the Statement object that produced this ResultSet object.
    override Statement getStatement() {
        checkClosed();
        lock();
        scope(exit) unlock();
        return stmt;
    }

    //Retrieves the current row number
    override int getRow() {
        checkClosed();
        lock();
        scope(exit) unlock();
        if (currentRowIndex <0 || currentRowIndex >= rowCount)
            return 0;
        return currentRowIndex + 1;
    }

    //Retrieves the fetch size for this ResultSet object.
    override int getFetchSize() {
        checkClosed();
        lock();
        scope(exit) unlock();
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
	public static string[string] setUserAndPassword(string username, string password) {
		string[string] params;
        params["user"] = username;
        params["password"] = password;
		return params;
    }
    override ddbc.core.Connection connect(string url, string[string] params) {
        //writeln("MySQLDriver.connect " ~ url);
        return new MySQLConnection(url, params);
    }
}

unittest {
    if (MYSQL_TESTS_ENABLED) {

        import std.conv;

        DataSource ds = createUnitTestMySQLDataSource();

        auto conn = ds.getConnection();
        scope(exit) conn.close();
        auto stmt = conn.createStatement();
        scope(exit) stmt.close();

        assert(stmt.executeUpdate("DROP TABLE IF EXISTS ddbct1") == 0);
        assert(stmt.executeUpdate("CREATE TABLE IF NOT EXISTS ddbct1 (id bigint not null primary key, name varchar(250), comment mediumtext)") == 0);
        assert(stmt.executeUpdate("INSERT INTO ddbct1 SET id=1, name='name1', comment='comment for line 1'") == 1);
        assert(stmt.executeUpdate("INSERT INTO ddbct1 SET id=2, name='name2', comment='comment for line 2 - can be very long'") == 1);
        assert(stmt.executeUpdate("INSERT INTO ddbct1 SET id=3, name='name3', comment='this is line 3'") == 1);
        assert(stmt.executeUpdate("INSERT INTO ddbct1 SET id=4, name='name4', comment=NULL") == 1);
        assert(stmt.executeUpdate("INSERT INTO ddbct1 SET id=5, name=NULL, comment=''") == 1);
        assert(stmt.executeUpdate("INSERT INTO ddbct1 SET id=6, name='', comment=NULL") == 1);
        assert(stmt.executeUpdate("UPDATE ddbct1 SET name=concat(name, '_x') WHERE id IN (3, 4)") == 2);
        
        PreparedStatement ps = conn.prepareStatement("UPDATE ddbct1 SET name=? WHERE id=?");
        ps.setString(1, null);
        ps.setLong(2, 3);
        assert(ps.executeUpdate() == 1);
        
        auto rs = stmt.executeQuery("SELECT id, name name_alias, comment FROM ddbct1 ORDER BY id");

        // testing result set meta data
        ResultSetMetaData meta = rs.getMetaData();
        assert(meta.getColumnCount() == 3);
        assert(meta.getColumnName(1) == "id");
        assert(meta.getColumnLabel(1) == "id");
        assert(meta.isNullable(1) == false);
        assert(meta.isNullable(2) == true);
        assert(meta.isNullable(3) == true);
        assert(meta.getColumnName(2) == "name");
        assert(meta.getColumnLabel(2) == "name_alias");
        assert(meta.getColumnName(3) == "comment");

        int rowCount = rs.getFetchSize();
        assert(rowCount == 6);
        int index = 1;
        while (rs.next()) {
            assert(!rs.isNull(1));
            ubyte[] bytes = rs.getBytes(3);
            int rowIndex = rs.getRow();
            assert(rowIndex == index);
            long id = rs.getLong(1);
            assert(id == index);
            writeln("field2 = '" ~ rs.getString(2) ~ "'");
            writeln("field3 = '" ~ rs.getString(3) ~ "'");
            writeln("wasNull = " ~ to!string(rs.wasNull()));
            if (id == 4) {
                assert(rs.getString(2) == "name4_x");
                assert(rs.isNull(3));
            }
            if (id == 5) {
                assert(rs.isNull(2));
                assert(!rs.isNull(3));
            }
            if (id == 6) {
                assert(!rs.isNull(2));
                assert(rs.isNull(3));
            }
            //writeln(to!string(rs.getLong(1)) ~ "\t" ~ rs.getString(2) ~ "\t" ~ strNull(rs.getString(3)) ~ "\t[" ~ to!string(bytes.length) ~ "]");
            index++;
        }
        
        PreparedStatement ps2 = conn.prepareStatement("SELECT id, name, comment FROM ddbct1 WHERE id >= ?");
        ps2.setLong(1, 3);
        rs = ps2.executeQuery();
        while (rs.next()) {
            //writeln(to!string(rs.getLong(1)) ~ "\t" ~ rs.getString(2) ~ "\t" ~ strNull(rs.getString(3)));
            index++;
        }
    }
}
