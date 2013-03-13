module ddbc.core;

import std.exception;

class SQLException : Exception {
	this(string msg, string f = __FILE__, size_t l = __LINE__) { super(msg, f, l); }
}

interface Connection {
	/// Releases this Connection object's database and JDBC resources immediately instead of waiting for them to be automatically released.
	void close();
	/// Makes all changes made since the previous commit/rollback permanent and releases any database locks currently held by this Connection object.
	void commit();
	/// Retrieves this Connection object's current catalog name.
	string getCatalog();
	/// Sets the given catalog name in order to select a subspace of this Connection object's database in which to work.
	void setCatalog(string catalog);
	/// Retrieves whether this Connection object has been closed.
	bool isClosed();
	/// Undoes all changes made in the current transaction and releases any database locks currently held by this Connection object.
	void rollback();
	/// Retrieves the current auto-commit mode for this Connection object.
	bool getAutoCommit();
	/// Sets this connection's auto-commit mode to the given state.
	void setAutoCommit(bool autoCommit);
	// statements
	/// Creates a Statement object for sending SQL statements to the database.
	Statement createStatement();
	/// Creates a PreparedStatement object for sending parameterized SQL statements to the database.
	PreparedStatement prepareStatement(string query);
}

interface ResultSetMetaData {
	//Returns the number of columns in this ResultSet object.
	int getColumnCount();

	// Gets the designated column's table's catalog name.
	string getCatalogName(int column);
	// Returns the fully-qualified name of the Java class whose instances are manufactured if the method ResultSet.getObject is called to retrieve a value from the column.
	//string getColumnClassName(int column);
	// Indicates the designated column's normal maximum width in characters.
	int getColumnDisplaySize(int column);
	// Gets the designated column's suggested title for use in printouts and displays.
	string getColumnLabel(int column);
	// Get the designated column's name.
	string getColumnName(int column);
	// Retrieves the designated column's SQL type.
	int getColumnType(int column);
	// Retrieves the designated column's database-specific type name.
	string getColumnTypeName(int column);
	// Get the designated column's number of decimal digits.
	int getPrecision(int column);
	// Gets the designated column's number of digits to right of the decimal point.
	int getScale(int column);
	// Get the designated column's table's schema.
	string getSchemaName(int column);
	// Gets the designated column's table name.
	string getTableName(int column);
	// Indicates whether the designated column is automatically numbered, thus read-only.
	bool isAutoIncrement(int column);
	// Indicates whether a column's case matters.
	bool isCaseSensitive(int column);
	// Indicates whether the designated column is a cash value.
	bool isCurrency(int column);
	// Indicates whether a write on the designated column will definitely succeed.
	bool isDefinitelyWritable(int column);
	// Indicates the nullability of values in the designated column.
	int isNullable(int column);
	// Indicates whether the designated column is definitely not writable.
	bool isReadOnly(int column);
	// Indicates whether the designated column can be used in a where clause.
	bool isSearchable(int column);
	// Indicates whether values in the designated column are signed numbers.
	bool isSigned(int column);
	// Indicates whether it is possible for a write on the designated column to succeed.
	bool isWritable(int column);
}

interface ParameterMetaData {
	// Retrieves the fully-qualified name of the Java class whose instances should be passed to the method PreparedStatement.setObject.
	//String getParameterClassName(int param);
	/// Retrieves the number of parameters in the PreparedStatement object for which this ParameterMetaData object contains information.
	int getParameterCount();
	/// Retrieves the designated parameter's mode.
	int getParameterMode(int param);
	/// Retrieves the designated parameter's SQL type.
	int getParameterType(int param);
	/// Retrieves the designated parameter's database-specific type name.
	string getParameterTypeName(int param);
	/// Retrieves the designated parameter's number of decimal digits.
	int getPrecision(int param);
	/// Retrieves the designated parameter's number of digits to right of the decimal point.
	int getScale(int param);
	/// Retrieves whether null values are allowed in the designated parameter.
	int isNullable(int param);
	/// Retrieves whether values for the designated parameter can be signed numbers.
	bool isSigned(int param);
}

interface DataSetReader {
	bool getBoolean(int columnIndex);
	ubyte getUbyte(int columnIndex);
	ubyte[] getBytes(int columnIndex);
	byte getByte(int columnIndex);
	short getShort(int columnIndex);
	ushort getUshort(int columnIndex);
	int getInt(int columnIndex);
	uint getUint(int columnIndex);
	long getLong(int columnIndex);
	ulong getUlong(int columnIndex);
	double getDouble(int columnIndex);
	float getFloat(int columnIndex);
	string getString(int columnIndex);
	bool isNull(int columnIndex);
	bool wasNull();
}

interface DataSetWriter {
	void setBoolean(int parameterIndex, bool x);
	void setLong(int parameterIndex, long x);
	void setInt(int parameterIndex, int x);
	void setShort(int parameterIndex, short x);
	void setByte(int parameterIndex, byte x);
	void setBytes(int parameterIndex, byte[] x);
	void setUlong(int parameterIndex, ulong x);
	void setUint(int parameterIndex, uint x);
	void setUshort(int parameterIndex, ushort x);
	void setUbyte(int parameterIndex, ubyte x);
	void setUbytes(int parameterIndex, ubyte[] x);
	void setString(int parameterIndex, string x);
	
	void setNull(int parameterIndex);
	void setNull(int parameterIndex, int sqlType);
}

interface ResultSet : DataSetReader {
	void close();
	bool first();
	bool isFirst();
	bool isLast();
	bool next();

	//Retrieves the number, types and properties of this ResultSet object's columns
	ResultSetMetaData getMetaData();
	//Retrieves the Statement object that produced this ResultSet object.
	Statement getStatement();
	//Retrieves the current row number
	int getRow();
	//Retrieves the fetch size for this ResultSet object.
	int getFetchSize();

	// from DataSetReader
	bool getBoolean(int columnIndex);
	ubyte getUbyte(int columnIndex);
	ubyte[] getBytes(int columnIndex);
	byte getByte(int columnIndex);
	short getShort(int columnIndex);
	ushort getUshort(int columnIndex);
	int getInt(int columnIndex);
	uint getUint(int columnIndex);
	long getLong(int columnIndex);
	ulong getUlong(int columnIndex);
	double getDouble(int columnIndex);
	float getFloat(int columnIndex);
	string getString(int columnIndex);
	bool isNull(int columnIndex);
	bool wasNull();

	// additional methods
	int findColumn(string columnName);
	bool getBoolean(string columnName);
	ubyte getUbyte(string columnName);
	ubyte[] getBytes(string columnName);
	byte getByte(string columnName);
	short getShort(string columnName);
	ushort getUshort(string columnName);
	int getInt(string columnName);
	uint getUint(string columnName);
	long getLong(string columnName);
	ulong getUlong(string columnName);
	double getDouble(string columnName);
	float getFloat(string columnName);
    string getString(string columnName);
}

interface Statement {
	ResultSet executeQuery(string query);
	int executeUpdate(string query);
	void close();
}

/// An object that represents a precompiled SQL statement. 
interface PreparedStatement : Statement, DataSetWriter {
	/// Executes the SQL statement in this PreparedStatement object, which must be an SQL INSERT, UPDATE or DELETE statement; or an SQL statement that returns nothing, such as a DDL statement.
	int executeUpdate();
	/// Executes the SQL query in this PreparedStatement object and returns the ResultSet object generated by the query.
	ResultSet executeQuery();

	/// Retrieves a ResultSetMetaData object that contains information about the columns of the ResultSet object that will be returned when this PreparedStatement object is executed.
	ResultSetMetaData getMetaData();
	/// Retrieves the number, types and properties of this PreparedStatement object's parameters.
	ParameterMetaData getParameterMetaData();
	/// Clears the current parameter values immediately.
	void clearParameters();

	// from DataSetWriter
	void setBoolean(int parameterIndex, bool x);
	void setLong(int parameterIndex, long x);
	void setInt(int parameterIndex, int x);
	void setShort(int parameterIndex, short x);
	void setByte(int parameterIndex, byte x);
	void setBytes(int parameterIndex, byte[] x);
	void setUlong(int parameterIndex, ulong x);
	void setUint(int parameterIndex, uint x);
	void setUshort(int parameterIndex, ushort x);
	void setUbyte(int parameterIndex, ubyte x);
	void setUbytes(int parameterIndex, ubyte[] x);
	void setString(int parameterIndex, string x);

	void setNull(int parameterIndex);
	void setNull(int parameterIndex, int sqlType);
}

interface Driver {
	Connection connect(string url, string[string] params);
}

interface DataSource {
	Connection getConnection();
}
