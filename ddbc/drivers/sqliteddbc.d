/**
 * DDBC - D DataBase Connector - abstraction layer for RDBMS access, with interface similar to JDBC. 
 * 
 * Source file ddbc/drivers/pgsqlddbc.d.
 *
 * DDBC library attempts to provide implementation independent interface to different databases.
 * 
 * Set of supported RDBMSs can be extended by writing Drivers for particular DBs.
 * 
 * JDBC documentation can be found here:
 * $(LINK http://docs.oracle.com/javase/1.5.0/docs/api/java/sql/package-summary.html)$(BR)
 *
 * This module contains implementation of SQLite Driver
 * 
 * You can find usage examples in unittest{} sections.
 *
 * Copyright: Copyright 2013
 * License:   $(LINK www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Author:   Vadim Lopatin
 */
module ddbc.drivers.sqliteddbc;

import std.algorithm;
import std.conv;
import std.datetime;
import std.exception;
import std.stdio;
import std.string;
import std.variant;
import core.sync.mutex;
import ddbc.common;
import ddbc.core;
import ddbc.drivers.sqlite;
import ddbc.drivers.utils;

version(USE_SQLITE) {

version(unittest) {
    /*
        To allow unit tests using PostgreSQL server,
     */
    /// change to false to disable tests on real PostgreSQL server
    immutable bool SQLITE_TESTS_ENABLED = true;
    /// change parameters if necessary
    const string SQLITE_UNITTEST_FILENAME = "ddbctest.sqlite";

    static if (SQLITE_TESTS_ENABLED) {
        /// use this data source for tests
        DataSource createUnitTestSQLITEDataSource() {
            SQLITEDriver driver = new SQLITEDriver();
            string[string] params;
            return new ConnectionPoolDataSourceImpl(driver, SQLITE_UNITTEST_FILENAME, params);
        }
    }
}

class SQLITEConnection : ddbc.core.Connection {
private:
    string filename;

    sqlite3 * conn;

    bool closed;
    bool autocommit;
    Mutex mutex;
    
    
    SQLITEStatement [] activeStatements;
    
    void closeUnclosedStatements() {
        SQLITEStatement [] list = activeStatements.dup;
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
    
    sqlite3 * getConnection() { return conn; }
    
    
    void onStatementClosed(SQLITEStatement stmt) {
        foreach(index, item; activeStatements) {
            if (item == stmt) {
                remove(activeStatements, index);
                return;
            }
        }
    }
    
    this(string url, string[string] params) {
        mutex = new Mutex();
        if (url.startsWith("sqlite::"))
            url = url[8 .. $];
        this.filename = url;
        writeln("trying to connect");
        int res = sqlite3_open(toStringz(filename), &conn);
        if(res != SQLITE_OK)
            throw new SQLException("SQLITE Error " ~ to!string(res) ~ " while trying to open DB " ~ filename);
        assert(conn !is null);
        closed = false;
        setAutoCommit(true);
    }
    
    override void close() {
        checkClosed();
        
        lock();
        scope(exit) unlock();
        
        closeUnclosedStatements();
        int res = sqlite3_close(conn);
        if (res != SQLITE_OK)
            throw new SQLException("SQLITE Error " ~ to!string(res) ~ " while trying to close DB " ~ filename);
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
        
        SQLITEStatement stmt = new SQLITEStatement(this);
        activeStatements ~= stmt;
        return stmt;
    }
    
    PreparedStatement prepareStatement(string sql) {
        checkClosed();
        
        lock();
        scope(exit) unlock();
        
        SQLITEPreparedStatement stmt = new SQLITEPreparedStatement(this, sql);
        activeStatements ~= stmt;
        return stmt;
    }
    
    override string getCatalog() {
        return "default";
    }
    
    /// Sets the given catalog name in order to select a subspace of this Connection object's database in which to work.
    override void setCatalog(string catalog) {
        checkClosed();
        throw new SQLException("Not implemented");
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
        stmt.executeUpdate("SET autocommit = " ~ (autoCommit ? "ON" : "OFF"));
        this.autocommit = autoCommit;
    }
}

class SQLITEStatement : Statement {
private:
    SQLITEConnection conn;
    //  Command * cmd;
    //  ddbc.drivers.mysql.ResultSet rs;
    SQLITEResultSet resultSet;
    
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
    
    this(SQLITEConnection conn) {
        this.conn = conn;
    }
    
//    ResultSetMetaData createMetadata(PGresult * res) {
//        int rows = PQntuples(res);
//        int fieldCount = PQnfields(res);
//        ColumnMetadataItem[] list = new ColumnMetadataItem[fieldCount];
//        for(int i = 0; i < fieldCount; i++) {
//            ColumnMetadataItem item = new ColumnMetadataItem();
//            //item.schemaName = field.db;
//            item.name = copyCString(PQfname(res, i));
//            //item.tableName = copyCString(PQfname(res, i));
//            int fmt = PQfformat(res, i);
//            ulong t = PQftype(res, i);
//            item.label = copyCString(PQfname(res, i));
//            //item.precision = field.length;
//            //item.scale = field.scale;
//            //item.isNullable = !field.notNull;
//            //item.isSigned = !field.unsigned;
//            //item.type = fromSQLITEType(field.type);
//            //          // TODO: fill more params
//            list[i] = item;
//        }
//        return new ResultSetMetaDataImpl(list);
//    }
    //  ParameterMetaData createMetadata(ParamDescription[] fields) {
    //      ParameterMetaDataItem[] res = new ParameterMetaDataItem[fields.length];
    //      foreach(i, field; fields) {
    //          ParameterMetaDataItem item = new ParameterMetaDataItem();
    //          item.precision = field.length;
    //          item.scale = field.scale;
    //          item.isNullable = !field.notNull;
    //          item.isSigned = !field.unsigned;
    //          item.type = fromSQLITEType(field.type);
    //          // TODO: fill more params
    //          res[i] = item;
    //      }
    //      return new ParameterMetaDataImpl(res);
    //  }
public:
    SQLITEConnection getConnection() {
        checkClosed();
        return conn;
    }
    
    override ddbc.core.ResultSet executeQuery(string query) {
        throw new SQLException("Not implemented");
        checkClosed();
        lock();
        scope(exit) unlock();
        
        //      cmd = new Command(conn.getConnection(), query);
        //      rs = cmd.execSQLResult();
        //      resultSet = new SQLITEResultSet(this, rs, createMetadata(cmd.getResultHeaders().getFieldDescriptions()));
        //      return resultSet;
    }
    
//    string getError() {
//        return copyCString(PQerrorMessage(conn.getConnection()));
//    }
    
    override int executeUpdate(string query) {
        Variant dummy;
        return executeUpdate(query, dummy);
    }
    
    override int executeUpdate(string query, out Variant insertId) {
        checkClosed();
        lock();
        scope(exit) unlock();

        // TODO:

        return 0;
    }
    
    override void close() {
        checkClosed();
        lock();
        scope(exit) unlock();
        closeResultSet();
        closed = true;
    }
    
    void closeResultSet() {
        //throw new SQLException("Not implemented");
        //      if (cmd == null) {
        //          return;
        //      }
        //      cmd.releaseStatement();
        //      delete cmd;
        //      cmd = null;
        //      if (resultSet !is null) {
        //          resultSet.onStatementClosed();
        //          resultSet = null;
        //      }
    }
}

class SQLITEPreparedStatement : SQLITEStatement, PreparedStatement {
    string query;
    int paramCount;

    sqlite3_stmt * stmt;

    bool done;

    ResultSetMetaData metadata;
    ParameterMetaData paramMetadata;
    this(SQLITEConnection conn, string query) {
        super(conn);
        this.query = query;

        int res = sqlite3_prepare_v2(
            conn.getConnection(),            /* Database handle */
            toStringz(query),       /* SQL statement, UTF-8 encoded */
            cast(int)query.length,              /* Maximum length of zSql in bytes. */
            &stmt,  /* OUT: Statement handle */
            null     /* OUT: Pointer to unused portion of zSql */
            );
        paramMetadata = createParamMetadata();
        metadata = createMetadata();
        enforceEx!SQLException(res == SQLITE_OK, "Error #" ~ to!string(res) ~ " while preparing statement " ~ query);
    }
    void checkIndex(int index) {
        if (index < 1 || index > paramCount)
            throw new SQLException("Parameter index " ~ to!string(index) ~ " is out of range");
    }
    ref Variant getParam(int index) {
        throw new SQLException("Not implemented");
        //      checkIndex(index);
        //      return cmd.param(cast(ushort)(index - 1));
    }
public:
    SqlType sqliteToSqlType(int t) {
        switch(t) {
            case SQLITE_INTEGER: return SqlType.BIGINT;
            case SQLITE_FLOAT: return SqlType.DOUBLE;
            case SQLITE_TEXT: return SqlType.VARCHAR;
            case SQLITE_BLOB: return SqlType.BLOB;
            case SQLITE_NULL: return SqlType.NULL;
            default:
                return SqlType.BLOB;
        }
    }

    ResultSetMetaData createMetadata() {
        int fieldCount = sqlite3_column_count(stmt);
        ColumnMetadataItem[] list = new ColumnMetadataItem[fieldCount];
        for(int i = 0; i < fieldCount; i++) {
            ColumnMetadataItem item = new ColumnMetadataItem();
            item.label = copyCString(sqlite3_column_origin_name(stmt, i));
            item.name = copyCString(sqlite3_column_name(stmt, i));
            item.schemaName = copyCString(sqlite3_column_database_name(stmt, i));
            item.tableName = copyCString(sqlite3_column_table_name(stmt, i));
            item.type = sqliteToSqlType(sqlite3_column_type(stmt, i));
            list[i] = item;
        }
        return new ResultSetMetaDataImpl(list);
    }

    ParameterMetaData createParamMetadata() {
        int fieldCount = sqlite3_bind_parameter_count(stmt);
        ParameterMetaDataItem[] res = new ParameterMetaDataItem[fieldCount];
        for(int i = 0; i < fieldCount; i++) {
            ParameterMetaDataItem item = new ParameterMetaDataItem();
            item.type = SqlType.VARCHAR;
            res[i] = item;
        }
        paramCount = fieldCount;
        return new ParameterMetaDataImpl(res);
    }

    override void close() {
        checkClosed();
        lock();
        scope(exit) unlock();

        closeResultSet();
        int res = sqlite3_finalize(stmt);
        enforceEx!SQLException(res == SQLITE_OK, "Error #" ~ to!string(res) ~ " while closing prepared statement " ~ query);
        closed = true;
    }

    
    /// Retrieves a ResultSetMetaData object that contains information about the columns of the ResultSet object that will be returned when this PreparedStatement object is executed.
    override ResultSetMetaData getMetaData() {
        checkClosed();
        lock();
        scope(exit) unlock();
        return metadata;
    }
    
    /// Retrieves the number, types and properties of this PreparedStatement object's parameters.
    override ParameterMetaData getParameterMetaData() {
        checkClosed();
        lock();
        scope(exit) unlock();
        return paramMetadata;
    }
    
    override int executeUpdate(out Variant insertId) {
        //throw new SQLException("Not implemented");
        checkClosed();
        lock();
        scope(exit) unlock();
        int rowsAffected = 0;
        int res = sqlite3_step(stmt);
        if (res == SQLITE_DONE) {
            insertId = Variant(sqlite3_last_insert_rowid(conn.getConnection()));
            rowsAffected = sqlite3_changes(conn.getConnection());
            done = true;
        } else if (res == SQLITE_ROW) {
            // row is available
            rowsAffected = -1;
        } else {
            enforceEx!SQLException(false, "Error #" ~ to!string(res) ~ " while trying to execute prepared statement: " ~ copyCString(sqlite3_errmsg(conn.getConnection())));
        }
        return rowsAffected;
    }
    
    override int executeUpdate() {
        Variant insertId;
        return executeUpdate(insertId);
    }
    
    override ddbc.core.ResultSet executeQuery() {
        int res = executeUpdate();
        enforceEx!SQLException(res == -1, "Query doesn't return result set");
        checkClosed();
        lock();
        scope(exit) unlock();
        resultSet = new SQLITEResultSet(this, stmt, getMetaData());
        return resultSet;
    }
    
    override void clearParameters() {
        throw new SQLException("Not implemented");
        //      checkClosed();
        //      lock();
        //      scope(exit) unlock();
        //      for (int i = 1; i <= paramCount; i++)
        //          setNull(i);
    }
    
    override void setFloat(int parameterIndex, float x) {
        throw new SQLException("Not implemented");
        //      checkClosed();
        //      lock();
        //      scope(exit) unlock();
        //      checkIndex(parameterIndex);
        //      cmd.param(parameterIndex-1) = x;
    }
    override void setDouble(int parameterIndex, double x){
        throw new SQLException("Not implemented");
        //      checkClosed();
        //      lock();
        //      scope(exit) unlock();
        //      checkIndex(parameterIndex);
        //      cmd.param(parameterIndex-1) = x;
    }
    override void setBoolean(int parameterIndex, bool x) {
        throw new SQLException("Not implemented");
        //      checkClosed();
        //      lock();
        //      scope(exit) unlock();
        //      checkIndex(parameterIndex);
        //      cmd.param(parameterIndex-1) = x;
    }
    override void setLong(int parameterIndex, long x) {
        throw new SQLException("Not implemented");
        //      checkClosed();
        //      lock();
        //      scope(exit) unlock();
        //      checkIndex(parameterIndex);
        //      cmd.param(parameterIndex-1) = x;
    }
    override void setUlong(int parameterIndex, ulong x) {
        throw new SQLException("Not implemented");
        //      checkClosed();
        //      lock();
        //      scope(exit) unlock();
        //      checkIndex(parameterIndex);
        //      cmd.param(parameterIndex-1) = x;
    }
    override void setInt(int parameterIndex, int x) {
        throw new SQLException("Not implemented");
        //      checkClosed();
        //      lock();
        //      scope(exit) unlock();
        //      checkIndex(parameterIndex);
        //      cmd.param(parameterIndex-1) = x;
    }
    override void setUint(int parameterIndex, uint x) {
        throw new SQLException("Not implemented");
        //      checkClosed();
        //      lock();
        //      scope(exit) unlock();
        //      checkIndex(parameterIndex);
        //      cmd.param(parameterIndex-1) = x;
    }
    override void setShort(int parameterIndex, short x) {
        throw new SQLException("Not implemented");
        //      checkClosed();
        //      lock();
        //      scope(exit) unlock();
        //      checkIndex(parameterIndex);
        //      cmd.param(parameterIndex-1) = x;
    }
    override void setUshort(int parameterIndex, ushort x) {
        throw new SQLException("Not implemented");
        //      checkClosed();
        //      lock();
        //      scope(exit) unlock();
        //      checkIndex(parameterIndex);
        //      cmd.param(parameterIndex-1) = x;
    }
    override void setByte(int parameterIndex, byte x) {
        throw new SQLException("Not implemented");
        //      checkClosed();
        //      lock();
        //      scope(exit) unlock();
        //      checkIndex(parameterIndex);
        //      cmd.param(parameterIndex-1) = x;
    }
    override void setUbyte(int parameterIndex, ubyte x) {
        throw new SQLException("Not implemented");
        //      checkClosed();
        //      lock();
        //      scope(exit) unlock();
        //      checkIndex(parameterIndex);
        //      cmd.param(parameterIndex-1) = x;
    }
    override void setBytes(int parameterIndex, byte[] x) {
        throw new SQLException("Not implemented");
        //      checkClosed();
        //      lock();
        //      scope(exit) unlock();
        //      checkIndex(parameterIndex);
        //      if (x == null)
        //          setNull(parameterIndex);
        //      else
        //          cmd.param(parameterIndex-1) = x;
    }
    override void setUbytes(int parameterIndex, ubyte[] x) {
        throw new SQLException("Not implemented");
        //      checkClosed();
        //      lock();
        //      scope(exit) unlock();
        //      checkIndex(parameterIndex);
        //      if (x == null)
        //          setNull(parameterIndex);
        //      else
        //          cmd.param(parameterIndex-1) = x;
    }
    override void setString(int parameterIndex, string x) {
        throw new SQLException("Not implemented");
        //      checkClosed();
        //      lock();
        //      scope(exit) unlock();
        //      checkIndex(parameterIndex);
        //      if (x == null)
        //          setNull(parameterIndex);
        //      else
        //          cmd.param(parameterIndex-1) = x;
    }
    override void setDateTime(int parameterIndex, DateTime x) {
        throw new SQLException("Not implemented");
        //      checkClosed();
        //      lock();
        //      scope(exit) unlock();
        //      checkIndex(parameterIndex);
        //      cmd.param(parameterIndex-1) = x;
    }
    override void setDate(int parameterIndex, Date x) {
        throw new SQLException("Not implemented");
        //      checkClosed();
        //      lock();
        //      scope(exit) unlock();
        //      checkIndex(parameterIndex);
        //      cmd.param(parameterIndex-1) = x;
    }
    override void setTime(int parameterIndex, TimeOfDay x) {
        throw new SQLException("Not implemented");
        //      checkClosed();
        //      lock();
        //      scope(exit) unlock();
        //      checkIndex(parameterIndex);
        //      cmd.param(parameterIndex-1) = x;
    }
    override void setVariant(int parameterIndex, Variant x) {
        throw new SQLException("Not implemented");
        //      checkClosed();
        //      lock();
        //      scope(exit) unlock();
        //      checkIndex(parameterIndex);
        //      if (x == null)
        //          setNull(parameterIndex);
        //      else
        //          cmd.param(parameterIndex-1) = x;
    }
    override void setNull(int parameterIndex) {
        throw new SQLException("Not implemented");
        //      checkClosed();
        //      lock();
        //      scope(exit) unlock();
        //      checkIndex(parameterIndex);
        //      cmd.setNullParam(parameterIndex-1);
    }
    override void setNull(int parameterIndex, int sqlType) {
        throw new SQLException("Not implemented");
        //      checkClosed();
        //      lock();
        //      scope(exit) unlock();
        //      setNull(parameterIndex);
    }
}

class SQLITEResultSet : ResultSetImpl {
    private SQLITEStatement stmt;
    private sqlite3_stmt * rs;
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
        lastIsNull = false; //rs[currentRowIndex].isNull(columnIndex - 1);
        Variant res;
//        if (!lastIsNull)
//            res = rs[currentRowIndex][columnIndex - 1];
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
    
    this(SQLITEStatement stmt, sqlite3_stmt * rs, ResultSetMetaData metadata) {
        this.stmt = stmt;
        this.rs = rs;
        this.metadata = metadata;
        closed = false;
//        rowCount = cast(int)rs.length;
//        currentRowIndex = -1;
//        columnMap = rs.getColNameMap();
//        columnCount = cast(int)rs.getColNames().length;
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
    override byte[] getBytes(int columnIndex) {
        checkClosed();
        lock();
        scope(exit) unlock();
        Variant v = getValue(columnIndex);
        if (lastIsNull)
            return null;
        if (v.convertsTo!(byte[])) {
            return v.get!(byte[]);
        }
        throw new SQLException("Cannot convert field " ~ to!string(columnIndex) ~ " to byte[]");
    }
    override ubyte[] getUbytes(int columnIndex) {
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
    override std.datetime.DateTime getDateTime(int columnIndex) {
        checkClosed();
        lock();
        scope(exit) unlock();
        Variant v = getValue(columnIndex);
        if (lastIsNull)
            return DateTime();
        if (v.convertsTo!(DateTime)) {
            return v.get!DateTime();
        }
        throw new SQLException("Cannot convert field " ~ to!string(columnIndex) ~ " to DateTime");
    }
    override std.datetime.Date getDate(int columnIndex) {
        checkClosed();
        lock();
        scope(exit) unlock();
        Variant v = getValue(columnIndex);
        if (lastIsNull)
            return Date();
        if (v.convertsTo!(Date)) {
            return v.get!Date();
        }
        throw new SQLException("Cannot convert field " ~ to!string(columnIndex) ~ " to Date");
    }
    override std.datetime.TimeOfDay getTime(int columnIndex) {
        checkClosed();
        lock();
        scope(exit) unlock();
        Variant v = getValue(columnIndex);
        if (lastIsNull)
            return TimeOfDay();
        if (v.convertsTo!(TimeOfDay)) {
            return v.get!TimeOfDay();
        }
        throw new SQLException("Cannot convert field " ~ to!string(columnIndex) ~ " to TimeOfDay");
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
        return false; //rs[currentRowIndex].isNull(columnIndex - 1);
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

//String url = "jdbc:postgresql://localhost/test";
//Properties props = new Properties();
//props.setProperty("user","fred");
//props.setProperty("password","secret");
//props.setProperty("ssl","true");
//Connection conn = DriverManager.getConnection(url, props);
class SQLITEDriver : Driver {
    // helper function
    public static string generateUrl(string host, ushort port, string dbname) {
        return "postgresql://" ~ host ~ ":" ~ to!string(port) ~ "/" ~ dbname;
    }
    public static string[string] setUserAndPassword(string username, string password) {
        string[string] params;
        params["user"] = username;
        params["password"] = password;
        params["ssl"] = "true";
        return params;
    }
    override ddbc.core.Connection connect(string url, string[string] params) {
        //writeln("SQLITEDriver.connect " ~ url);
        return new SQLITEConnection(url, params);
    }
}

unittest {
    if (SQLITE_TESTS_ENABLED) {
        
        import std.conv;
        DataSource ds = createUnitTestSQLITEDataSource();
        writeln("trying to open connection");        
        auto conn = ds.getConnection();
        writeln("connection is opened");        
        assert(conn !is null);
        scope(exit) conn.close();
    }
}

} else { // version(USE_SQLITE)
    version(unittest) {
        immutable bool SQLITE_TESTS_ENABLED = false;
    }
}