module ddbc.common;
import ddbc.core;
import std.algorithm;
import std.exception;

class DataSourceImpl : DataSource {
	Driver driver;
	string url;
	string[string] params;
	this(Driver driver, string url, string[string]params) {
		this.driver = driver;
		this.url = url;
		this.params = params;
	}
	override Connection getConnection() {
		return driver.connect(url, params);
	}
}

interface ConnectionCloseHandler {
	void onConnectionClosed(Connection connection);
}

class ConnectionWrapper : Connection {
	private ConnectionCloseHandler pool;
	private Connection base;
	private bool closed;

	this(ConnectionCloseHandler pool, Connection base) {
		this.pool = pool;
		this.base = base;
	}
	override void close() { 
		assert(!closed, "Connection is already closed");
		closed = true; 
		pool.onConnectionClosed(base); 
	}
	override PreparedStatement prepareStatement(string query) { return base.prepareStatement(query); }
	override void commit() { base.commit(); }
	override Statement createStatement() { return base.createStatement(); }
	override string getCatalog() { return base.getCatalog(); }
	override bool isClosed() { return closed; }
	override void rollback() { base.rollback(); }
	override bool getAutoCommit() { return base.getAutoCommit(); }
	override void setAutoCommit(bool autoCommit) { base.setAutoCommit(autoCommit); }
	override void setCatalog(string catalog) { base.setCatalog(catalog); }
}

// TODO: implement limits
// TODO: thread safety
class ConnectionPoolDataSourceImpl : DataSourceImpl, ConnectionCloseHandler {
private:
	int maxPoolSize;
	int timeToLive;
	int waitTimeOut;

	Connection [] activeConnections;
	Connection [] freeConnections;

public:

	this(Driver driver, string url, string[string]params, int maxPoolSize, int timeToLive, int waitTimeOut) {
		super(driver, url, params);
		this.maxPoolSize = maxPoolSize;
		this.timeToLive = timeToLive;
		this.waitTimeOut = waitTimeOut;
	}

	override Connection getConnection() {
		Connection conn = null;
		if (freeConnections.length > 0) {
			conn = freeConnections[$-1];
			remove(freeConnections, freeConnections.length - 1);
		} else {
			conn = super.getConnection();
		}
		activeConnections ~= conn;
		auto wrapper = new ConnectionWrapper(this, conn);
		return wrapper;
	}

	void removeUsed(Connection connection) {
		foreach (i, item; activeConnections) {
			if (item == connection) {
				std.algorithm.remove(activeConnections, i);
				return;
			}
		}
		throw new SQLException("Connection being closed is not found in pool");
	}

	override void onConnectionClosed(Connection connection) {
		removeUsed(connection);
		freeConnections ~= connection;
	}
}

// Helper implementation of ResultSet - throws Method not implemented for most of methods.
class ResultSetImpl : ddbc.core.ResultSet {
public:
	override void close() {
		throw new SQLException("Method not implemented");
	}
	override bool first() {
		throw new SQLException("Method not implemented");
	}
	override bool isFirst() {
		throw new SQLException("Method not implemented");
	}
	override bool isLast() {
		throw new SQLException("Method not implemented");
	}
	override bool next() {
		throw new SQLException("Method not implemented");
	}
	
	override int findColumn(string columnName) {
		throw new SQLException("Method not implemented");
	}
	override bool getBoolean(int columnIndex) {
		throw new SQLException("Method not implemented");
	}
	override bool getBoolean(string columnName) {
		return getBoolean(findColumn(columnName));
	}
	override ubyte getUbyte(int columnIndex) {
		throw new SQLException("Method not implemented");
	}
	override ubyte getUbyte(string columnName) {
		return getUbyte(findColumn(columnName));
	}
	override byte getByte(int columnIndex) {
		throw new SQLException("Method not implemented");
	}
	override byte getByte(string columnName) {
		return getByte(findColumn(columnName));
	}
	override ubyte[] getBytes(int columnIndex) {
		throw new SQLException("Method not implemented");
	}
	override ubyte[] getBytes(string columnName) {
		return getBytes(findColumn(columnName));
	}
	override short getShort(int columnIndex) {
		throw new SQLException("Method not implemented");
	}
	override short getShort(string columnName) {
		return getShort(findColumn(columnName));
	}
	override ushort getUshort(int columnIndex) {
		throw new SQLException("Method not implemented");
	}
	override ushort getUshort(string columnName) {
		return getUshort(findColumn(columnName));
	}
	override int getInt(int columnIndex) {
		throw new SQLException("Method not implemented");
	}
	override int getInt(string columnName) {
		return getInt(findColumn(columnName));
	}
	override uint getUint(int columnIndex) {
		throw new SQLException("Method not implemented");
	}
	override uint getUint(string columnName) {
		return getUint(findColumn(columnName));
	}
	override long getLong(int columnIndex) {
		throw new SQLException("Method not implemented");
	}
	override long getLong(string columnName) {
		return getLong(findColumn(columnName));
	}
	override ulong getUlong(int columnIndex) {
		throw new SQLException("Method not implemented");
	}
	override ulong getUlong(string columnName) {
		return getUlong(findColumn(columnName));
	}
	override double getDouble(int columnIndex) {
		throw new SQLException("Method not implemented");
	}
	override double getDouble(string columnName) {
		return getDouble(findColumn(columnName));
	}
	override float getFloat(int columnIndex) {
		throw new SQLException("Method not implemented");
	}
	override float getFloat(string columnName) {
		return getFloat(findColumn(columnName));
	}
	override string getString(int columnIndex) {
		throw new SQLException("Method not implemented");
	}
	override string getString(string columnName) {
		return getString(findColumn(columnName));
	}
	override bool wasNull() {
		throw new SQLException("Method not implemented");
	}

	override bool isNull(int columnIndex) {
		throw new SQLException("Method not implemented");
	}

	//Retrieves the number, types and properties of this ResultSet object's columns
	override ResultSetMetaData getMetaData() {
		throw new SQLException("Method not implemented");
	}
	//Retrieves the Statement object that produced this ResultSet object.
	override Statement getStatement() {
		throw new SQLException("Method not implemented");
	}
	//Retrieves the current row number
	override int getRow() {
		throw new SQLException("Method not implemented");
	}
	//Retrieves the fetch size for this ResultSet object.
	override int getFetchSize() {
		throw new SQLException("Method not implemented");
	}
}

class ColumnMetadataItem {
	string 	catalogName;
	int	    displaySize;
	string 	label;
	string  name;
	int 	type;
	string 	typeName;
	int     precision;
	int     scale;
	string  schemaName;
	string  tableName;
	bool 	isAutoIncrement;
	bool 	isCaseSensitive;
	bool 	isCurrency;
	bool 	isDefinitelyWritable;
	int 	isNullable;
	bool 	isReadOnly;
	bool 	isSearchable;
	bool 	isSigned;
	bool 	isWritable;
}

class ParameterMetaDataItem {
	/// Retrieves the designated parameter's mode.
	int mode;
	/// Retrieves the designated parameter's SQL type.
	int type;
	/// Retrieves the designated parameter's database-specific type name.
	string typeName;
	/// Retrieves the designated parameter's number of decimal digits.
	int precision;
	/// Retrieves the designated parameter's number of digits to right of the decimal point.
	int scale;
	/// Retrieves whether null values are allowed in the designated parameter.
	int isNullable;
	/// Retrieves whether values for the designated parameter can be signed numbers.
	bool isSigned;
}

class ParameterMetaDataImpl : ParameterMetaData {
	ParameterMetaDataItem [] cols;
	this(ParameterMetaDataItem [] cols) {
		this.cols = cols;
	}
	ref ParameterMetaDataItem col(int column) {
		enforceEx!SQLException(column >=1 && column <= cols.length, "Parameter index out of range");
		return cols[column - 1];
	}
	// Retrieves the fully-qualified name of the Java class whose instances should be passed to the method PreparedStatement.setObject.
	//String getParameterClassName(int param);
	/// Retrieves the number of parameters in the PreparedStatement object for which this ParameterMetaData object contains information.
	int getParameterCount() {
		return cast(int)cols.length;
	}
	/// Retrieves the designated parameter's mode.
	int getParameterMode(int param) { return col(param).mode; }
	/// Retrieves the designated parameter's SQL type.
	int getParameterType(int param) { return col(param).type; }
	/// Retrieves the designated parameter's database-specific type name.
	string getParameterTypeName(int param) { return col(param).typeName; }
	/// Retrieves the designated parameter's number of decimal digits.
	int getPrecision(int param) { return col(param).precision; }
	/// Retrieves the designated parameter's number of digits to right of the decimal point.
	int getScale(int param) { return col(param).scale; }
	/// Retrieves whether null values are allowed in the designated parameter.
	int isNullable(int param) { return col(param).isNullable; }
	/// Retrieves whether values for the designated parameter can be signed numbers.
	bool isSigned(int param) { return col(param).isSigned; }
}

class ResultSetMetaDataImpl : ResultSetMetaData {
	ColumnMetadataItem [] cols;
	this(ColumnMetadataItem [] cols) {
		this.cols = cols;
	}
	ref ColumnMetadataItem col(int column) {
		enforceEx!SQLException(column >=1 && column <= cols.length, "Column index out of range");
		return cols[column - 1];
	}
	//Returns the number of columns in this ResultSet object.
	override int getColumnCount() { return cast(int)cols.length; }
	// Gets the designated column's table's catalog name.
	override string getCatalogName(int column) { return col(column).catalogName; }
	// Returns the fully-qualified name of the Java class whose instances are manufactured if the method ResultSet.getObject is called to retrieve a value from the column.
	//override string getColumnClassName(int column) { return col(column).catalogName; }
	// Indicates the designated column's normal maximum width in characters.
	override int getColumnDisplaySize(int column) { return col(column).displaySize; }
	// Gets the designated column's suggested title for use in printouts and displays.
	override string getColumnLabel(int column) { return col(column).label; }
	// Get the designated column's name.
	override string getColumnName(int column) { return col(column).name; }
	// Retrieves the designated column's SQL type.
	override int getColumnType(int column) { return col(column).type; }
	// Retrieves the designated column's database-specific type name.
	override string getColumnTypeName(int column) { return col(column).typeName; }
	// Get the designated column's number of decimal digits.
	override int getPrecision(int column) { return col(column).precision; }
	// Gets the designated column's number of digits to right of the decimal point.
	override int getScale(int column) { return col(column).scale; }
	// Get the designated column's table's schema.
	override string getSchemaName(int column) { return col(column).schemaName; }
	// Gets the designated column's table name.
	override string getTableName(int column) { return col(column).tableName; }
	// Indicates whether the designated column is automatically numbered, thus read-only.
	override bool isAutoIncrement(int column) { return col(column).isAutoIncrement; }
	// Indicates whether a column's case matters.
	override bool isCaseSensitive(int column) { return col(column).isCaseSensitive; }
	// Indicates whether the designated column is a cash value.
	override bool isCurrency(int column) { return col(column).isCurrency; }
	// Indicates whether a write on the designated column will definitely succeed.
	override bool isDefinitelyWritable(int column) { return col(column).isDefinitelyWritable; }
	// Indicates the nullability of values in the designated column.
	override int isNullable(int column) { return col(column).isNullable; }
	// Indicates whether the designated column is definitely not writable.
	override bool isReadOnly(int column) { return col(column).isReadOnly; }
	// Indicates whether the designated column can be used in a where clause.
	override bool isSearchable(int column) { return col(column).isSearchable; }
	// Indicates whether values in the designated column are signed numbers.
	override bool isSigned(int column) { return col(column).isSigned; }
	// Indicates whether it is possible for a write on the designated column to succeed.
	override bool isWritable(int column) { return col(column).isWritable; }
}
