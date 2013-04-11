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


version(USE_SQLITE) {

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
    //import ddbc.drivers.sqlite;
    import ddbc.drivers.utils;
    import etc.c.sqlite3;


    version (Windows) {
        pragma (lib, "sqlite3.lib");
    } else version (linux) {
        pragma (lib, "sqlite3");
    } else version (Posix) {
        pragma (lib, "libsqlite3.so");
    } else version (darwin) {
        pragma (lib, "libsqlite3.so");
    } else {
        pragma (msg, "You will need to manually link in the SQLite library.");
    } 

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

        private string getError() {
            return copyCString(sqlite3_errmsg(conn));
        }

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
            //writeln("trying to connect");
            int res = sqlite3_open(toStringz(filename), &conn);
            if(res != SQLITE_OK)
                throw new SQLException("SQLITE Error " ~ to!string(res) ~ " while trying to open DB " ~ filename ~ " : " ~ getError());
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
                throw new SQLException("SQLITE Error " ~ to!string(res) ~ " while trying to close DB " ~ filename ~ " : " ~ getError());
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
            //TODO:
            //stmt.executeUpdate("ROLLBACK");
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
            //TODO:
            //stmt.executeUpdate("SET autocommit = " ~ (autoCommit ? "ON" : "OFF"));
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
        
    public:
        SQLITEConnection getConnection() {
            checkClosed();
            return conn;
        }

        private PreparedStatement _currentStatement;
        private ResultSet _currentResultSet;

        private void closePreparedStatement() {
            if (_currentResultSet !is null) {
                _currentResultSet.close();
                _currentResultSet = null;
            }
            if (_currentStatement !is null) {
                _currentStatement.close();
                _currentStatement = null;
            }
        }

        override ddbc.core.ResultSet executeQuery(string query) {
            closePreparedStatement();
            _currentStatement = conn.prepareStatement(query);
            _currentResultSet = _currentStatement.executeQuery();
            return _currentResultSet;
        }
        
    //    string getError() {
    //        return copyCString(PQerrorMessage(conn.getConnection()));
    //    }
        
        override int executeUpdate(string query) {
            Variant dummy;
            return executeUpdate(query, dummy);
        }
        
        override int executeUpdate(string query, out Variant insertId) {
            closePreparedStatement();
            _currentStatement = conn.prepareStatement(query);
            return _currentStatement.executeUpdate(insertId);
        }
        
        override void close() {
            checkClosed();
            lock();
            scope(exit) unlock();
            closePreparedStatement();
            closed = true;
        }
        
        void closeResultSet() {
        }
    }

    class SQLITEPreparedStatement : SQLITEStatement, PreparedStatement {
        string query;
        int paramCount;

        sqlite3_stmt * stmt;

        bool done;
        bool preparing;

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
            enforceEx!SQLException(res == SQLITE_OK, "Error #" ~ to!string(res) ~ " while preparing statement " ~ query ~ " : " ~ conn.getError());
            paramMetadata = createParamMetadata();
            paramCount = paramMetadata.getParameterCount();
            metadata = createMetadata();
            resetParams();
            preparing = true;
        }
        bool[] paramIsSet;
        void resetParams() {
            paramIsSet = new bool[paramCount];
        }
        // before execution of query
        private void allParamsSet() {
            for(int i = 0; i < paramCount; i++) {
                enforceEx!SQLException(paramIsSet[i], "Parameter " ~ to!string(i + 1) ~ " is not set");
            }
            if (preparing) {
                preparing = false;
            } else {
                closeResultSet();
                sqlite3_reset(stmt);
            }
        }
        // before setting any parameter
        private void checkIndex(int index) {
            if (index < 1 || index > paramCount)
                throw new SQLException("Parameter index " ~ to!string(index) ~ " is out of range");
            if (!preparing) {
                closeResultSet();
                sqlite3_reset(stmt);
                preparing = true;
            }
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
                case SQLITE3_TEXT: return SqlType.VARCHAR;
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
            enforceEx!SQLException(res == SQLITE_OK, "Error #" ~ to!string(res) ~ " while closing prepared statement " ~ query ~ " : " ~ conn.getError());
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
            allParamsSet();

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
                enforceEx!SQLException(false, "Error #" ~ to!string(res) ~ " while trying to execute prepared statement: "  ~ " : " ~ conn.getError());
            }
            return rowsAffected;
        }
        
        override int executeUpdate() {
            Variant insertId;
            return executeUpdate(insertId);
        }
        
        override ddbc.core.ResultSet executeQuery() {
            checkClosed();
            lock();
            scope(exit) unlock();
            allParamsSet();
            enforceEx!SQLException(metadata.getColumnCount() > 0, "Query doesn't return result set");
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
            setDouble(parameterIndex, x);
        }
        override void setDouble(int parameterIndex, double x){
            checkClosed();
            lock();
            scope(exit) unlock();
            checkIndex(parameterIndex);
            sqlite3_bind_double(stmt, parameterIndex, x);
            paramIsSet[parameterIndex - 1] = true;
        }
        override void setBoolean(int parameterIndex, bool x) {
            setLong(parameterIndex, x ? 1 : 0);
        }
        override void setLong(int parameterIndex, long x) {
            checkClosed();
            lock();
            scope(exit) unlock();
            checkIndex(parameterIndex);
            sqlite3_bind_int64(stmt, parameterIndex, x);
            paramIsSet[parameterIndex - 1] = true;
        }
        override void setUlong(int parameterIndex, ulong x) {
            setLong(parameterIndex, cast(long)x);
        }
        override void setInt(int parameterIndex, int x) {
            setLong(parameterIndex, cast(long)x);
        }
        override void setUint(int parameterIndex, uint x) {
            setLong(parameterIndex, cast(long)x);
        }
        override void setShort(int parameterIndex, short x) {
            setLong(parameterIndex, cast(long)x);
        }
        override void setUshort(int parameterIndex, ushort x) {
            setLong(parameterIndex, cast(long)x);
        }
        override void setByte(int parameterIndex, byte x) {
            setLong(parameterIndex, cast(long)x);
        }
        override void setUbyte(int parameterIndex, ubyte x) {
            setLong(parameterIndex, cast(long)x);
        }
        override void setBytes(int parameterIndex, byte[] x) {
            checkClosed();
            lock();
            scope(exit) unlock();
            checkIndex(parameterIndex);
            if (x is null) {
                setNull(parameterIndex);
                return;
            }
            sqlite3_bind_blob(stmt, parameterIndex, cast(const (void *))x.ptr, cast(int)x.length, SQLITE_TRANSIENT);
            paramIsSet[parameterIndex - 1] = true;
        }
        override void setUbytes(int parameterIndex, ubyte[] x) {
            checkClosed();
            lock();
            scope(exit) unlock();
            checkIndex(parameterIndex);
            if (x is null) {
                setNull(parameterIndex);
                return;
            }
            sqlite3_bind_blob(stmt, parameterIndex, cast(const char *)x.ptr, cast(int)x.length, SQLITE_TRANSIENT);
            paramIsSet[parameterIndex - 1] = true;
        }
        override void setString(int parameterIndex, string x) {
            checkClosed();
            lock();
            scope(exit) unlock();
            checkIndex(parameterIndex);
            if (x is null) {
                setNull(parameterIndex);
                return;
            }
            sqlite3_bind_text(stmt, parameterIndex, cast(const char *)x.ptr, cast(int)x.length, SQLITE_TRANSIENT);
            paramIsSet[parameterIndex - 1] = true;
        }
        override void setDateTime(int parameterIndex, DateTime x) {
            setString(parameterIndex, x.toISOString());
        }
        override void setDate(int parameterIndex, Date x) {
            setString(parameterIndex, x.toISOString());
        }
        override void setTime(int parameterIndex, TimeOfDay x) {
            setString(parameterIndex, x.toISOString());
        }
        override void setVariant(int parameterIndex, Variant x) {
            if (x == null)
                setNull(parameterIndex);
            else if (x.convertsTo!long)
                setLong(parameterIndex, x.get!long);
            else if (x.convertsTo!ulong)
                setLong(parameterIndex, x.get!ulong);
            else if (x.convertsTo!double)
                setDouble(parameterIndex, x.get!double);
            else if (x.convertsTo!(byte[]))
                setBytes(parameterIndex, x.get!(byte[]));
            else if (x.convertsTo!(ubyte[]))
                setUbytes(parameterIndex, x.get!(ubyte[]));
            else if (x.convertsTo!DateTime)
                setDateTime(parameterIndex, x.get!DateTime);
            else if (x.convertsTo!Date)
                setDate(parameterIndex, x.get!Date);
            else if (x.convertsTo!TimeOfDay)
                setTime(parameterIndex, x.get!TimeOfDay);
            else
                setString(parameterIndex, x.toString);
        }
        override void setNull(int parameterIndex) {
            checkClosed();
            lock();
            scope(exit) unlock();
            checkIndex(parameterIndex);
            sqlite3_bind_null(stmt, parameterIndex);
            paramIsSet[parameterIndex - 1] = true;
        }
        override void setNull(int parameterIndex, int sqlType) {
            setNull(parameterIndex);
        }
    }

    class SQLITEResultSet : ResultSetImpl {
        private SQLITEStatement stmt;
        private sqlite3_stmt * rs;
        ResultSetMetaData metadata;
        private bool closed;
        private int currentRowIndex;
//        private int rowCount;
        private int[string] columnMap;
        private bool lastIsNull;
        private int columnCount;

        private bool _last;
        private bool _first;

        // checks index, updates lastIsNull, returns column type
        int checkIndex(int columnIndex) {
            enforceEx!SQLException(columnIndex >= 1 && columnIndex <= columnCount, "Column index out of bounds: " ~ to!string(columnIndex));
            int res = sqlite3_column_type(rs, columnIndex - 1);
            lastIsNull = (res == SQLITE_NULL);
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
            this.columnCount = sqlite3_data_count(rs); //metadata.getColumnCount();
            for (int i=0; i<columnCount; i++) {
                columnMap[metadata.getColumnName(i + 1)] = i;
            }
            currentRowIndex = -1;
            _first = true;
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
            if (closed)
                return;
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
            throw new SQLException("Not implemented");
        }
        override bool isFirst() {
            checkClosed();
            lock();
            scope(exit) unlock();
            return _first;
        }
        override bool isLast() {
            checkClosed();
            lock();
            scope(exit) unlock();
            return _last;
        }

        override bool next() {
            checkClosed();
            lock();
            scope(exit) unlock();

            if (_first) {
                _first = false;
                //writeln("next() first time invocation, columnCount=" ~ to!string(columnCount));
                //return columnCount > 0;
            }

            int res = sqlite3_step(rs);
            if (res == SQLITE_DONE) {
                _last = true;
                columnCount = sqlite3_data_count(rs);
                //writeln("sqlite3_step = SQLITE_DONE columnCount=" ~ to!string(columnCount));
                // end of data
                return columnCount > 0;
            } else if (res == SQLITE_ROW) {
                //writeln("sqlite3_step = SQLITE_ROW");
                // have a row
                currentRowIndex++;
                columnCount = sqlite3_data_count(rs);
                return true;
            } else {
                enforceEx!SQLException(false, "Error #" ~ to!string(res) ~ " while reading query result: " ~ copyCString(sqlite3_errmsg(stmt.conn.getConnection())));
                return false;
            }
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
            return getLong(columnIndex) != 0;
        }
        override ubyte getUbyte(int columnIndex) {
            return cast(ubyte)getLong(columnIndex);
        }
        override byte getByte(int columnIndex) {
            return cast(byte)getLong(columnIndex);
        }
        override short getShort(int columnIndex) {
            return cast(short)getLong(columnIndex);
        }
        override ushort getUshort(int columnIndex) {
            return cast(ushort)getLong(columnIndex);
        }
        override int getInt(int columnIndex) {
            return cast(int)getLong(columnIndex);
        }
        override uint getUint(int columnIndex) {
            return cast(uint)getLong(columnIndex);
        }
        override long getLong(int columnIndex) {
            checkClosed();
            checkIndex(columnIndex);
            lock();
            scope(exit) unlock();
            auto v = sqlite3_column_int64(rs, columnIndex - 1);
            return v;
        }
        override ulong getUlong(int columnIndex) {
            return cast(ulong)getLong(columnIndex);
        }
        override double getDouble(int columnIndex) {
            checkClosed();
            checkIndex(columnIndex);
            lock();
            scope(exit) unlock();
            auto v = sqlite3_column_double(rs, columnIndex - 1);
            return v;
        }
        override float getFloat(int columnIndex) {
            return cast(float)getDouble(columnIndex);
        }
        override byte[] getBytes(int columnIndex) {
            checkClosed();
            checkIndex(columnIndex);
            lock();
            scope(exit) unlock();
            const byte * bytes = cast(const byte *)sqlite3_column_blob(rs, columnIndex - 1);
            int len = sqlite3_column_bytes(rs, columnIndex - 1);
            byte[] res = new byte[len];
            for (int i=0; i<len; i++)
                res[i] = bytes[i];
            return res;
        }
        override ubyte[] getUbytes(int columnIndex) {
            checkClosed();
            checkIndex(columnIndex);
            lock();
            scope(exit) unlock();
            const ubyte * bytes = cast(const ubyte *)sqlite3_column_blob(rs, columnIndex - 1);
            int len = sqlite3_column_bytes(rs, columnIndex - 1);
            ubyte[] res = new ubyte[len];
            for (int i=0; i<len; i++)
                res[i] = bytes[i];
            return res;
        }
        override string getString(int columnIndex) {
            checkClosed();
            checkIndex(columnIndex);
            lock();
            scope(exit) unlock();
            const char * bytes = cast(const char *)sqlite3_column_text(rs, columnIndex - 1);
            int len = sqlite3_column_bytes(rs, columnIndex - 1);
            char[] res = new char[len];
            for (int i=0; i<len; i++)
                res[i] = bytes[i];
            return cast(string)res;
        }
        override DateTime getDateTime(int columnIndex) {
            string s = getString(columnIndex);
            DateTime dt;
            if (s is null)
                return dt;
            try {
                return DateTime.fromISOString(s);
            } catch (Throwable e) {
                throw new SQLException("Cannot convert string to DateTime - " ~ s);
            }
        }
        override Date getDate(int columnIndex) {
            string s = getString(columnIndex);
            Date dt;
            if (s is null)
                return dt;
            try {
                return Date.fromISOString(s);
            } catch (Throwable e) {
                throw new SQLException("Cannot convert string to DateTime - " ~ s);
            }
        }
        override TimeOfDay getTime(int columnIndex) {
            string s = getString(columnIndex);
            TimeOfDay dt;
            if (s is null)
                return dt;
            try {
                return TimeOfDay.fromISOString(s);
            } catch (Throwable e) {
                throw new SQLException("Cannot convert string to DateTime - " ~ s);
            }
        }
        
        override Variant getVariant(int columnIndex) {
            checkClosed();
            int type = checkIndex(columnIndex);
            lock();
            scope(exit) unlock();
            Variant v = null;
            if (lastIsNull)
                return v;
            switch (type) {
                case SQLITE_INTEGER:
                    v = getLong(columnIndex);
                    break;
                case SQLITE_FLOAT:
                    v = getDouble(columnIndex);
                    break;
                case SQLITE3_TEXT:
                    v = getString(columnIndex);
                    break;
                case SQLITE_BLOB:
                    v = getUbytes(columnIndex);
                    break;
                default:
                    break;
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
            checkIndex(columnIndex);
            return lastIsNull;
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
            if (currentRowIndex <0)
                return 0;
            return currentRowIndex + 1;
        }
        
        //Retrieves the fetch size for this ResultSet object.
        override int getFetchSize() {
            checkClosed();
            lock();
            scope(exit) unlock();
            return -1;
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
            //writeln("trying to open connection");        
            auto conn = ds.getConnection();
            //writeln("connection is opened");        
            assert(conn !is null);
            scope(exit) conn.close();
            {
                //writeln("dropping table");
                Statement stmt = conn.createStatement();
                scope(exit) stmt.close();
                stmt.executeUpdate("DROP TABLE IF EXISTS t1");
            }
            {
                //writeln("creating table");
                Statement stmt = conn.createStatement();
                scope(exit) stmt.close();
                stmt.executeUpdate("CREATE TABLE IF NOT EXISTS t1 (id INTEGER PRIMARY KEY, name VARCHAR(255) NOT NULL, flags int null)");
            }
            {
                //writeln("populating table");
                PreparedStatement stmt = conn.prepareStatement("INSERT INTO t1 (name) VALUES ('test1'), ('test2')");
                scope(exit) stmt.close();
                Variant id = 0;
                assert(stmt.executeUpdate(id) == 2);
                assert(id.get!long > 0);
            }
            {
                //writeln("reading table");
                Statement stmt = conn.createStatement();
                scope(exit) stmt.close();
                ResultSet rs = stmt.executeQuery("SELECT id, name, flags FROM t1");
                assert(rs.getMetaData().getColumnCount() == 3);
                assert(rs.getMetaData().getColumnName(1) == "id");
                assert(rs.getMetaData().getColumnName(2) == "name");
                assert(rs.getMetaData().getColumnName(3) == "flags");
                scope(exit) rs.close();
                //writeln("id" ~ "\t" ~ "name");
                while (rs.next()) {
                    long id = rs.getLong(1);
                    string name = rs.getString(2);
                    assert(rs.isNull(3));
                    //writeln("" ~ to!string(id) ~ "\t" ~ name);
                }
            }
            {
                //writeln("reading table with parameter id=1");
                PreparedStatement stmt = conn.prepareStatement("SELECT id, name, flags FROM t1 WHERE id = ?");
                scope(exit) stmt.close();
                assert(stmt.getMetaData().getColumnCount() == 3);
                assert(stmt.getMetaData().getColumnName(1) == "id");
                assert(stmt.getMetaData().getColumnName(2) == "name");
                assert(stmt.getMetaData().getColumnName(3) == "flags");
                stmt.setLong(1, 1);
                {
                    ResultSet rs = stmt.executeQuery();
                    scope(exit) rs.close();
                    //writeln("id" ~ "\t" ~ "name");
                    while (rs.next()) {
                        long id = rs.getLong(1);
                        string name = rs.getString(2);
                        assert(rs.isNull(3));
                        //writeln("" ~ to!string(id) ~ "\t" ~ name);
                    }
                }
                //writeln("changing parameter id=2");
                stmt.setLong(1, 2);
                {
                    ResultSet rs = stmt.executeQuery();
                    scope(exit) rs.close();
                    //writeln("id" ~ "\t" ~ "name");
                    while (rs.next()) {
                        long id = rs.getLong(1);
                        string name = rs.getString(2);
                        //writeln("" ~ to!string(id) ~ "\t" ~ name);
                    }
                }
            }
        }
    }

} else { // version(USE_SQLITE)
    version(unittest) {
        immutable bool SQLITE_TESTS_ENABLED = false;
    }
}