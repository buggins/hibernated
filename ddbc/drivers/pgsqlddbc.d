/**
 * DDBC - D DataBase Connector - abstraction layer for RDBMS access, with interface similar to JDBC. 
 * 
 * Source file ddbc/drivers/pgsqlddbc.d.
 *
 * DDBC library attempts to provide implementation independent interface to different databases.
 * 
 * Set of supported RDBMSs can be extended by writing Drivers for particular DBs.
 * Currently it only includes MySQL driver.
 * 
 * JDBC documentation can be found here:
 * $(LINK http://docs.oracle.com/javase/1.5.0/docs/api/java/sql/package-summary.html)$(BR)
 *
 * This module contains implementation of PostgreSQL Driver
 * 
 *
 * You can find usage examples in unittest{} sections.
 *
 * Copyright: Copyright 2013
 * License:   $(LINK www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Author:   Vadim Lopatin
 */
module ddbc.drivers.pgsqlddbc;


version(USE_PGSQL) {

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
    import ddbc.drivers.pgsql;
    import ddbc.drivers.utils;

    version(unittest) {
    	/*
            To allow unit tests using PostgreSQL server,
         */
    	/// change to false to disable tests on real PostgreSQL server
    	immutable bool PGSQL_TESTS_ENABLED = true;
    	/// change parameters if necessary
    	const string PGSQL_UNITTEST_HOST = "localhost";
    	const int    PGSQL_UNITTEST_PORT = 5432;
    	const string PGSQL_UNITTEST_USER = "testuser";
    	const string PGSQL_UNITTEST_PASSWORD = "testpassword";
    	const string PGSQL_UNITTEST_DB = "testdb";
    	
    	static if (PGSQL_TESTS_ENABLED) {
    		/// use this data source for tests
    		DataSource createUnitTestPGSQLDataSource() {
    			PGSQLDriver driver = new PGSQLDriver();
    			string url = PGSQLDriver.generateUrl(PGSQL_UNITTEST_HOST, PGSQL_UNITTEST_PORT, PGSQL_UNITTEST_DB);
    			string[string] params = PGSQLDriver.setUserAndPassword(PGSQL_UNITTEST_USER, PGSQL_UNITTEST_PASSWORD);
    			return new ConnectionPoolDataSourceImpl(driver, url, params);
    		}
    	}
    }


    class PGSQLConnection : ddbc.core.Connection {
    private:
    	string url;
    	string[string] params;
    	string dbName;
    	string username;
    	string password;
    	string hostname;
    	int port = 5432;
    	PGconn * conn;
    	bool closed;
    	bool autocommit;
    	Mutex mutex;
    	
    	
    	PGSQLStatement [] activeStatements;
    	
    	void closeUnclosedStatements() {
    		PGSQLStatement [] list = activeStatements.dup;
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
    	
    	PGconn * getConnection() { return conn; }
    	
    	
    	void onStatementClosed(PGSQLStatement stmt) {
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
    				port = 5432;
    		}
    		username = params["user"];
    		password = params["password"];
    		
    		//writeln("host " ~ hostname ~ " : " ~ to!string(port) ~ " db=" ~ dbName ~ " user=" ~ username ~ " pass=" ~ password);

    		const char ** keywords = [std.string.toStringz("host"), std.string.toStringz("port"), std.string.toStringz("dbname"), std.string.toStringz("user"), std.string.toStringz("password"), null].ptr;
    		const char ** values = [std.string.toStringz(hostname), std.string.toStringz(to!string(port)), std.string.toStringz(dbName), std.string.toStringz(username), std.string.toStringz(password), null].ptr;
    		//writeln("trying to connect");
    		conn = PQconnectdbParams(keywords, values, 0);
    		if(conn is null)
    			throw new SQLException("Cannot get Postgres connection");
    		if(PQstatus(conn) != CONNECTION_OK)
    			throw new SQLException(copyCString(PQerrorMessage(conn)));
    		closed = false;
    		setAutoCommit(true);
    		updateConnectionParams();
    	}

    	void updateConnectionParams() {
    		Statement stmt = createStatement();
    		scope(exit) stmt.close();
    		stmt.executeUpdate("SET NAMES 'utf8'");
    	}

    	override void close() {
    		checkClosed();
    		
    		lock();
    		scope(exit) unlock();
    		
    		closeUnclosedStatements();
    		
    		PQfinish(conn);
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
    		
    		PGSQLStatement stmt = new PGSQLStatement(this);
    		activeStatements ~= stmt;
    		return stmt;
    	}
    	
    	PreparedStatement prepareStatement(string sql) {
    		checkClosed();
    		
    		lock();
    		scope(exit) unlock();
    		
    		PGSQLPreparedStatement stmt = new PGSQLPreparedStatement(this, sql);
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

    		// TODO:
    		throw new SQLException("Not implemented");
    		//conn.selectDB(catalog);
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
    		stmt.executeUpdate("SET autocommit = " ~ (autoCommit ? "ON" : "OFF"));
    		this.autocommit = autoCommit;
    	}
    }

    class PGSQLStatement : Statement {
    private:
    	PGSQLConnection conn;
    //	Command * cmd;
    //	ddbc.drivers.mysql.ResultSet rs;
    	PGSQLResultSet resultSet;
    	
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
    	
    	this(PGSQLConnection conn) {
    		this.conn = conn;
    	}
    	
    	ResultSetMetaData createMetadata(PGresult * res) {
    		int rows = PQntuples(res);
    		int fieldCount = PQnfields(res);
    		ColumnMetadataItem[] list = new ColumnMetadataItem[fieldCount];
    		for(int i = 0; i < fieldCount; i++) {
    			ColumnMetadataItem item = new ColumnMetadataItem();
    			//item.schemaName = field.db;
    			item.name = copyCString(PQfname(res, i));
                //item.tableName = copyCString(PQftable(res, i));
    			int fmt = PQfformat(res, i);
    			ulong t = PQftype(res, i);
    			item.label = copyCString(PQfname(res, i));
    			//item.precision = field.length;
    			//item.scale = field.scale;
    			//item.isNullable = !field.notNull;
    			//item.isSigned = !field.unsigned;
    			//item.type = fromPGSQLType(field.type);
    //			// TODO: fill more params
    			list[i] = item;
    		}
    		return new ResultSetMetaDataImpl(list);
    	}
    	ParameterMetaData createParameterMetadata(int paramCount) {
            ParameterMetaDataItem[] res = new ParameterMetaDataItem[paramCount];
            for(int i = 0; i < paramCount; i++) {
    			ParameterMetaDataItem item = new ParameterMetaDataItem();
    			item.precision = 0;
    			item.scale = 0;
    			item.isNullable = true;
    			item.isSigned = true;
    			item.type = SqlType.VARCHAR;
    			res[i] = item;
    		}
    		return new ParameterMetaDataImpl(res);
    	}
    public:
    	PGSQLConnection getConnection() {
    		checkClosed();
    		return conn;
    	}

        private void fillData(PGresult * res, ref Variant[][] data) {
            int rows = PQntuples(res);
            int fieldCount = PQnfields(res);
            int[] fmts = new int[fieldCount];
            int[] types = new int[fieldCount];
            for (int col = 0; col < fieldCount; col++) {
                fmts[col] = PQfformat(res, col);
                types[col] = cast(int)PQftype(res, col);
            }
            for (int row = 0; row < rows; row++) {
                Variant[] v = new Variant[fieldCount];
                for (int col = 0; col < fieldCount; col++) {
                    int n = PQgetisnull(res, row, col);
                    if (n != 0) {
                        v[col] = null;
                    } else {
                        int len = PQgetlength(res, row, col);
                        const char * value = PQgetvalue(res, row, col);
                        int t = types[col];
                        //writeln("[" ~ to!string(row) ~ "][" ~ to!string(col) ~ "] type = " ~ to!string(t) ~ " len = " ~ to!string(len));
                        if (fmts[col] == 0) {
                            // text
                            string s = copyCString(value, len);
                            //writeln("text: " ~ s);
                            switch(t) {
                                case INT4OID:
                                    v[col] = parse!int(s);
                                    break;
                                case BOOLOID:
                                    v[col] = s == "true" ? true : (s == "false" ? false : parse!int(s) != 0);
                                    break;
                                case CHAROID:
                                    v[col] = cast(char)(s.length > 0 ? s[0] : 0);
                                    break;
                                case INT8OID:
                                    v[col] = parse!long(s);
                                    break;
                                case INT2OID:
                                    v[col] = parse!short(s);
                                    break;
                                case FLOAT4OID:
                                    v[col] = parse!float(s);
                                    break;
                                case FLOAT8OID:
                                    v[col] = parse!double(s);
                                    break;
                                case VARCHAROID:
                                case TEXTOID:
                                case NAMEOID:
                                    v[col] = s;
                                    break;
                                case BYTEAOID:
                                    v[col] = byteaToUbytes(s);
                                    break;
                                default:
                                    throw new SQLException("Unsupported column type " ~ to!string(t));
                            }
                        } else {
                            // binary
                            //writeln("binary:");
                            byte[] b = new byte[len];
                            for (int i=0; i<len; i++)
                                b[i] = value[i];
                            v[col] = b;
                        }
                    }
                }
                data ~= v;
            }
        }

    	override ddbc.core.ResultSet executeQuery(string query) {
    		//throw new SQLException("Not implemented");
    		checkClosed();
    		lock();
    		scope(exit) unlock();

    		PGresult * res = PQexec(conn.getConnection(), std.string.toStringz(query));
    		enforceEx!SQLException(res !is null, "Failed to execute statement " ~ query);
    		auto status = PQresultStatus(res);
    		enforceEx!SQLException(status == PGRES_TUPLES_OK, getError());
    		scope(exit) PQclear(res);

    //		cmd = new Command(conn.getConnection(), query);
    //		rs = cmd.execSQLResult();
            auto metadata = createMetadata(res);
            int rows = PQntuples(res);
            int fieldCount = PQnfields(res);
            Variant[][] data;
            fillData(res, data);
            resultSet = new PGSQLResultSet(this, data, metadata);
    		return resultSet;
    	}

    	string getError() {
    		return copyCString(PQerrorMessage(conn.getConnection()));
    	}

    	override int executeUpdate(string query) {
    		Variant dummy;
    		return executeUpdate(query, dummy);
    	}

        void readInsertId(PGresult * res, ref Variant insertId) {
            int rows = PQntuples(res);
            int fieldCount = PQnfields(res);
            //writeln("readInsertId - rows " ~ to!string(rows) ~ " " ~ to!string(fieldCount));
            if (rows == 1 && fieldCount == 1) {
                int len = PQgetlength(res, 0, 0);
                const char * value = PQgetvalue(res, 0, 0);
                string s = copyCString(value, len);
                insertId = parse!long(s);
            }
        }

    	override int executeUpdate(string query, out Variant insertId) {
    		checkClosed();
    		lock();
    		scope(exit) unlock();
    		PGresult * res = PQexec(conn.getConnection(), std.string.toStringz(query));
    		enforceEx!SQLException(res !is null, "Failed to execute statement " ~ query);
    		auto status = PQresultStatus(res);
    		enforceEx!SQLException(status == PGRES_COMMAND_OK || status == PGRES_TUPLES_OK, getError());
    		scope(exit) PQclear(res);
    		
    		string rowsAffected = copyCString(PQcmdTuples(res));

            readInsertId(res, insertId);
//    		auto lastid = PQoidValue(res);
//            writeln("lastId = " ~ to!string(lastid));
            int affected = rowsAffected.length > 0 ? to!int(rowsAffected) : 0;
//    		insertId = Variant(cast(long)lastid);
    		return affected;
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
    //		if (cmd == null) {
    //			return;
    //		}
    //		cmd.releaseStatement();
    //		delete cmd;
    //		cmd = null;
    //		if (resultSet !is null) {
    //			resultSet.onStatementClosed();
    //			resultSet = null;
    //		}
    	}
    }

    ulong preparedStatementIndex = 1;

    class PGSQLPreparedStatement : PGSQLStatement, PreparedStatement {
    	string query;
    	int paramCount;
    	ResultSetMetaData metadata;
    	ParameterMetaData paramMetadata;
        string stmtName;
        bool[] paramIsSet;
        string[] paramValue;
        //PGresult * rs;

        string convertParams(string query) {
            string res;
            int count = 0;
            bool insideString = false;
            char lastChar = 0;
            foreach(ch; query) {
                if (ch == '\'') {
                    if (insideString) {
                        if (lastChar != '\\')
                            insideString = false;
                    } else {
                        insideString = true;
                    }
                    res ~= ch;
                } else if (ch == '?') {
                    if (!insideString) {
                        count++;
                        res ~= "$" ~ to!string(count);
                    } else {
                        res ~= ch;
                    }
                } else {
                    res ~= ch;
                }
                lastChar = ch;
            }
            paramCount = count;
            return res;
        }

    	this(PGSQLConnection conn, string query) {
    		super(conn);
            query = convertParams(query);
            this.query = query;
            paramMetadata = createParameterMetadata(paramCount);
            stmtName = "ddbcstmt" ~ to!string(preparedStatementIndex);
            paramIsSet = new bool[paramCount];
            paramValue = new string[paramCount];
//            rs = PQprepare(conn.getConnection(),
//                                toStringz(stmtName),
//                                toStringz(query),
//                                paramCount,
//                                null);
//            enforceEx!SQLException(rs !is null, "Error while preparing statement " ~ query);
//            auto status = PQresultStatus(rs);
            //writeln("prepare paramCount = " ~ to!string(paramCount));
//            enforceEx!SQLException(status == PGRES_COMMAND_OK || status == PGRES_TUPLES_OK, "Error while preparing statement " ~ query ~ " : " ~ getError(rs));
//            metadata = createMetadata(rs);
            //scope(exit) PQclear(rs);
        }
        string getError(PGresult * res) {
            return copyCString(PQresultErrorMessage(res));
        }
    	void checkIndex(int index) {
    		if (index < 1 || index > paramCount)
    			throw new SQLException("Parameter index " ~ to!string(index) ~ " is out of range");
    	}
        void checkParams() {
            foreach(i, b; paramIsSet)
                enforceEx!SQLException(b, "Parameter " ~ to!string(i) ~ " is not set");
        }
    	void setParam(int index, string value) {
    		checkIndex(index);
    		paramValue[index - 1] = value;
            paramIsSet[index - 1] = true;
    	}

        PGresult * exec() {
            checkParams();
            const (char) * [] values = new const(char)*[paramCount];
            int[] lengths = new int[paramCount];
            int[] formats = new int[paramCount];
            for (int i=0; i<paramCount; i++) {
                if (paramValue[i] is null)
                    values[i] = null;
                else
                    values[i] = toStringz(paramValue[i]);
                lengths[i] = cast(int)paramValue[i].length;
            }
//            PGresult * res = PQexecPrepared(conn.getConnection(),
//                                            toStringz(stmtName),
//                                            paramCount,
//                                            cast(const char * *)values.ptr,
//                                            cast(const int *)lengths.ptr,
//                                            cast(const int *)formats.ptr,
//                                            0);
            PGresult * res = PQexecParams(conn.getConnection(),
                                 toStringz(query),
                                 paramCount,
                                 null,
                                 cast(const char * *)values.ptr,
                                 cast(const int *)lengths.ptr,
                                 cast(const int *)formats.ptr,
                                 0);
            enforceEx!SQLException(res !is null, "Error while executing prepared statement " ~ query);
            metadata = createMetadata(res);
            return res;
        }

    public:
    	
        override void close() {
            checkClosed();
            lock();
            scope(exit) unlock();
            //PQclear(rs);
            closeResultSet();
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
    		//throw new SQLException("Not implemented");
    		checkClosed();
    		lock();
    		scope(exit) unlock();
    		return paramMetadata;
    	}
    	
    	override int executeUpdate() {
            Variant dummy;
            return executeUpdate(dummy);
    	}
    	
    	override int executeUpdate(out Variant insertId) {
    		checkClosed();
    		lock();
    		scope(exit) unlock();
            PGresult * res = exec();
            scope(exit) PQclear(res);
            auto status = PQresultStatus(res);
            enforceEx!SQLException(status == PGRES_COMMAND_OK || status == PGRES_TUPLES_OK, getError(res));

            string rowsAffected = copyCString(PQcmdTuples(res));
            //auto lastid = PQoidValue(res);
            readInsertId(res, insertId);
            //writeln("lastId = " ~ to!string(lastid));
            int affected = rowsAffected.length > 0 ? to!int(rowsAffected) : 0;
            //insertId = Variant(cast(long)lastid);
            return affected;
        }
    	
    	override ddbc.core.ResultSet executeQuery() {
    		checkClosed();
    		lock();
    		scope(exit) unlock();
            PGresult * res = exec();
            scope(exit) PQclear(res);
            int rows = PQntuples(res);
            int fieldCount = PQnfields(res);
            Variant[][] data;
            fillData(res, data);
            resultSet = new PGSQLResultSet(this, data, metadata);
            return resultSet;
        }
    	
    	override void clearParameters() {
    		throw new SQLException("Not implemented");
    //		checkClosed();
    //		lock();
    //		scope(exit) unlock();
    //		for (int i = 1; i <= paramCount; i++)
    //			setNull(i);
    	}
    	
    	override void setFloat(int parameterIndex, float x) {
            checkClosed();
            lock();
            scope(exit) unlock();
            setParam(parameterIndex, to!string(x));
        }
    	override void setDouble(int parameterIndex, double x){
            checkClosed();
            lock();
            scope(exit) unlock();
            setParam(parameterIndex, to!string(x));
        }
    	override void setBoolean(int parameterIndex, bool x) {
            checkClosed();
            lock();
            scope(exit) unlock();
            setParam(parameterIndex, x ? "true" : "false");
        }
    	override void setLong(int parameterIndex, long x) {
    		checkClosed();
    		lock();
    		scope(exit) unlock();
            setParam(parameterIndex, to!string(x));
    	}

        override void setUlong(int parameterIndex, ulong x) {
            checkClosed();
            lock();
            scope(exit) unlock();
            setParam(parameterIndex, to!string(x));
        }

        override void setInt(int parameterIndex, int x) {
            checkClosed();
            lock();
            scope(exit) unlock();
            setParam(parameterIndex, to!string(x));
        }

        override void setUint(int parameterIndex, uint x) {
            checkClosed();
            lock();
            scope(exit) unlock();
            setParam(parameterIndex, to!string(x));
        }

        override void setShort(int parameterIndex, short x) {
            checkClosed();
            lock();
            scope(exit) unlock();
            setParam(parameterIndex, to!string(x));
        }

        override void setUshort(int parameterIndex, ushort x) {
            checkClosed();
            lock();
            scope(exit) unlock();
            setParam(parameterIndex, to!string(x));
        }
  
        override void setByte(int parameterIndex, byte x) {
            checkClosed();
            lock();
            scope(exit) unlock();
            setParam(parameterIndex, to!string(x));
        }
 
        override void setUbyte(int parameterIndex, ubyte x) {
            checkClosed();
            lock();
            scope(exit) unlock();
            checkIndex(parameterIndex);
            setParam(parameterIndex, to!string(x));
        }
   
        override void setBytes(int parameterIndex, byte[] x) {
            setString(parameterIndex, bytesToBytea(x));
        }
    	override void setUbytes(int parameterIndex, ubyte[] x) {
            setString(parameterIndex, ubytesToBytea(x));
        }
    	override void setString(int parameterIndex, string x) {
            checkClosed();
            lock();
            scope(exit) unlock();
            setParam(parameterIndex, x);
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
            checkClosed();
            lock();
            scope(exit) unlock();
            if (x.convertsTo!DateTime)
                setDateTime(parameterIndex, x.get!DateTime);
            else if (x.convertsTo!Date)
                setDate(parameterIndex, x.get!Date);
            else if (x.convertsTo!TimeOfDay)
                setTime(parameterIndex, x.get!TimeOfDay);
            else if (x.convertsTo!(byte[]))
                setBytes(parameterIndex, x.get!(byte[]));
            else if (x.convertsTo!(ubyte[]))
                setUbytes(parameterIndex, x.get!(ubyte[]));
            else
                setParam(parameterIndex, x.toString);
        }

        override void setNull(int parameterIndex) {
            checkClosed();
            lock();
            scope(exit) unlock();
            setParam(parameterIndex, null);
        }

        override void setNull(int parameterIndex, int sqlType) {
            checkClosed();
            lock();
            scope(exit) unlock();
            setParam(parameterIndex, null);
        }
    }

    class PGSQLResultSet : ResultSetImpl {
    	private PGSQLStatement stmt;
        private Variant[][] data;
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
    		Variant res = data[currentRowIndex][columnIndex - 1];
            lastIsNull = (res == null);
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
    	
    	this(PGSQLStatement stmt, Variant[][] data, ResultSetMetaData metadata) {
    		this.stmt = stmt;
    		this.data = data;
    		this.metadata = metadata;
    		closed = false;
    		rowCount = cast(int)data.length;
    		currentRowIndex = -1;
    		columnCount = metadata.getColumnCount();
            for (int i=0; i<columnCount; i++) {
                columnMap[metadata.getColumnName(i + 1)] = i;
            }
            //writeln("created result set: " ~ to!string(rowCount) ~ " rows, " ~ to!string(columnCount) ~ " cols");
        }
    	
    	void onStatementClosed() {
    		closed = true;
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
    			return to!uint(v.get!(ulong));
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
            return byteaToBytes(v.toString);
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
            return byteaToUbytes(v.toString);
        }
    	override string getString(int columnIndex) {
    		checkClosed();
    		lock();
    		scope(exit) unlock();
    		Variant v = getValue(columnIndex);
    		if (lastIsNull)
    			return null;
//    		if (v.convertsTo!(ubyte[])) {
//    			// assume blob encoding is utf-8
//    			// TODO: check field encoding
//    			return decodeTextBlob(v.get!(ubyte[]));
//    		}
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
    		return data[currentRowIndex][columnIndex - 1] == null;
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
    class PGSQLDriver : Driver {
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
    		//writeln("PGSQLDriver.connect " ~ url);
    		return new PGSQLConnection(url, params);
    	}
    }

    unittest {
    	static if (PGSQL_TESTS_ENABLED) {
    		
    		import std.conv;
    		DataSource ds = createUnitTestPGSQLDataSource();
    	
    		auto conn = ds.getConnection();
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
                stmt.executeUpdate("CREATE TABLE IF NOT EXISTS t1 (id SERIAL, name VARCHAR(255) NOT NULL, flags int null)");
                //writeln("populating table");
                Variant id = 0;
                assert(stmt.executeUpdate("INSERT INTO t1 (name) VALUES ('test1') returning id", id) == 1);
                assert(id.get!long > 0);
            }
            {
                PreparedStatement stmt = conn.prepareStatement("INSERT INTO t1 (name) VALUES ('test2') returning id");
                scope(exit) stmt.close();
                Variant id = 0;
                assert(stmt.executeUpdate(id) == 1);
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
                    //writeln("calling getLong");
                    long id = rs.getLong(1);
                    //writeln("done getLong");
                    string name = rs.getString(2);
                    assert(rs.isNull(3));
                    //writeln("" ~ to!string(id) ~ "\t" ~ name);
                }
            }
            {
                //writeln("reading table with parameter id=1");
                PreparedStatement stmt = conn.prepareStatement("SELECT id, name, flags FROM t1 WHERE id = ?");
                scope(exit) stmt.close();
//                assert(stmt.getMetaData().getColumnCount() == 3);
//                assert(stmt.getMetaData().getColumnName(1) == "id");
//                assert(stmt.getMetaData().getColumnName(2) == "name");
//                assert(stmt.getMetaData().getColumnName(3) == "flags");
                //writeln("calling setLong");
                stmt.setLong(1, 1);
                //writeln("done setLong");
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
                //writeln("calling setLong");
                stmt.setLong(1, 2);
                //writeln("done setLong");
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

} else { // version(USE_PGSQL)
    immutable bool PGSQL_TESTS_ENABLED = false;
}
