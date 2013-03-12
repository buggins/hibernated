module ddbc.drivers.mysqlddbc;

import ddbc.core;
import ddbc.common;

class MySQLConnection : Connection {
private:
    string url;
    string[string] params;
public:
    this(string url, string[string] params) {
        this.url = url;
        this.params = params;
    }
    override void close() {
        // TODO:
    }
    override void commit() {
        // TODO:
    }
    override Statement * createStatement() {
        // TODO:
        return null;
    }
    override string getCatalog() {
        // TODO:
        return "";
    }
    override bool isClosed() {
        // TODO:
        return true;
    }
    override void rollback() {
        // TODO:
    }
    override bool getAutoCommit() {
        // TODO:
        return true;
    }
    override void setAutoCommit(bool autoCommit) {
        // TODO:
    }
}
// sample URL:
// mysql://localhost:3306/DatabaseName
class MySQLDriver : Driver {
    override Connection * connect(string url, string[string] params) {
        return null;
    }
}
