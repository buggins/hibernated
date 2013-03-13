module ddbc.common;
import ddbc.core;
import std.algorithm;

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
	override ResultSetMetadata getMetaData() {
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
