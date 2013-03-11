module ddbc.common;
import ddbc.core;
import std.algorithm;

class DataSourceImpl : DataSource {
	Driver * driver;
	string url;
	string[string] params;
	this(Driver * driver, string url, string[string]params) {
		this.driver = driver;
		this.url = url;
		this.params = params;
	}
	override Connection * getConnection() {
		return driver.connect(url, params);
	}
}

interface ConnectionCloseHandler {
	void onConnectionClosed(Connection * connection);
}

class ConnectionWrapper : Connection {
	private ConnectionCloseHandler * pool;
	private Connection * base;
	private bool closed;

	this(ConnectionCloseHandler * pool, Connection * base) {
		this.pool = pool;
		this.base = base;
	}
	override void close() { 
		assert(!closed, "Connection is already closed");
		closed = true; 
		pool.onConnectionClosed(base); 
	}
	override void commit() { base.commit(); }
	override Statement * createStatement() { return base.createStatement(); }
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

	Connection * [] activeConnections;
	Connection * [] freeConnections;

public:

	this(Driver * driver, string url, string[string]params, int maxPoolSize, int timeToLive, int waitTimeOut) {
		super(driver, url, params);
		this.maxPoolSize = maxPoolSize;
		this.timeToLive = timeToLive;
		this.waitTimeOut = waitTimeOut;
	}

	override Connection * getConnection() {
		Connection * conn = null;
		if (freeConnections.length > 0) {
			conn = freeConnections[$-1];
			remove(freeConnections, freeConnections.length - 1);
		} else {
			conn = super.getConnection();
		}
		activeConnections ~= conn;
		auto wrapper = new ConnectionWrapper(cast(ConnectionCloseHandler*)this, conn);
		return cast(Connection*)wrapper;
	}

	void removeUsed(Connection * connection) {
		foreach (i, item; activeConnections) {
			if (item == connection) {
				std.algorithm.remove(activeConnections, i);
				return;
			}
		}
		throw new SQLException("Connection being closed is not found in pool");
	}

	override void onConnectionClosed(Connection * connection) {
		removeUsed(connection);
		freeConnections ~= connection;
	}
}
