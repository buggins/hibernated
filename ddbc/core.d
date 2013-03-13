module ddbc.core;

import std.exception;

class SQLException : Exception {
	this(string msg, string f = __FILE__, size_t l = __LINE__) { super(msg, f, l); }
}

interface Connection {
	void close();
	void commit();
	string getCatalog();
	bool isClosed();
	void rollback();
	bool getAutoCommit();
	void setAutoCommit(bool autoCommit);
	// statements
	Statement createStatement();
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

interface ResultSet {
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

	int findColumn(string columnName);
	bool getBoolean(int columnIndex);
	bool getBoolean(string columnName);
	ubyte getUbyte(int columnIndex);
	ubyte getUbyte(string columnName);
	ubyte[] getBytes(int columnIndex);
	ubyte[] getBytes(string columnName);
	byte getByte(int columnIndex);
	byte getByte(string columnName);
	short getShort(int columnIndex);
	short getShort(string columnName);
	ushort getUshort(int columnIndex);
	ushort getUshort(string columnName);
	int getInt(int columnIndex);
	int getInt(string columnName);
	uint getUint(int columnIndex);
	uint getUint(string columnName);
	long getLong(int columnIndex);
	long getLong(string columnName);
	ulong getUlong(int columnIndex);
	ulong getUlong(string columnName);
	double getDouble(int columnIndex);
	double getDouble(string columnName);
	float getFloat(int columnIndex);
	float getFloat(string columnName);
	string getString(int columnIndex);
    string getString(string columnName);
	bool isNull(int columnIndex);
    bool wasNull();
}

interface Statement {
	ResultSet executeQuery(string query);
	int executeUpdate(string query);
	void close();
}

/// An object that represents a precompiled SQL statement. 
interface PreparedStatement : Statement {
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
