module ddbc.core;

class SQLException : Exception {
	this(string msg) { super(msg); }
}

interface Connection {
	void close();
	void commit();
	Statement createStatement();
	string getCatalog();
	bool isClosed();
	void rollback();
	bool getAutoCommit();
	void setAutoCommit(bool autoCommit);
}

interface ResultSetMetadata {
	int getColumnCount();
	string getColumnName(int columnIndex);
	string getColumnLabel(int columnIndex);
	int getColumnType(int columnIndex);
	bool isNullable(int columnIndex);
}

interface ResultSet {
	void close();
	bool first();
	bool isFirst();
	bool isLast();
	bool next();

	int findColumn(string columnName);
	bool getBoolean(int columnIndex);
	bool getBoolean(string columnName);
	int getInt(int columnIndex);
	int getInt(string columnName);
	long getLong(int columnIndex);
	long getLong(string columnName);
    string getString(int columnIndex);
    string getString(string columnName);
    bool wasNull();
}

interface Statement {
	ResultSet executeQuery(string query);
	int executeUpdate(string query);
	void close();
}

interface Driver {
	Connection connect(string url, string[string] params);
}

interface DataSource {
	Connection getConnection();
}
