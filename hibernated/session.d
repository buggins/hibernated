module hibernated.session;

import std.algorithm;
import std.conv;
import std.stdio;
import std.exception;
import std.variant;

import ddbc.core;
import ddbc.common;

import hibernated.type;
import hibernated.dialect;
import hibernated.core;
import hibernated.metadata;

interface Transaction {
}

// similar to org.hibernate.Session
interface Session
{
	Transaction beginTransaction();
	void cancelQuery();
	void clear();
	Connection close();

    ///Does this session contain any changes which must be synchronized with the database? In other words, would any DML operations be executed if we flushed this session?
    bool isDirty();
    /// Check if the session is still open.
    bool isOpen();
    /// Check if the session is currently connected.
    bool isConnected();
    /// Check if this instance is associated with this Session.
    bool contains(Object object);
	SessionFactory getSessionFactory();
	string getEntityName(Object object);
    /// Return the persistent instance of the given named entity with the given identifier, or null if there is no such persistent instance.
	Object get(string entityName, Variant id);
    /// Read the persistent state associated with the given identifier into the given transient instance.
    Object load(string entityName, Variant id);
    /// Read the persistent state associated with the given identifier into the given transient instance
    void load(Object obj, Variant id);
    /// Re-read the state of the given instance from the underlying database.
	void refresh(Object obj);
    /// Persist the given transient instance, first assigning a generated identifier.
	Object save(Object obj);
    /// Update the persistent instance with the identifier of the given detached instance.
	string update(Object object);
    /// renamed from Session.delete
    void remove(Object object);

}

/// Allows reaction to basic SessionFactory occurrences
interface SessionFactoryObserver {
    ///Callback to indicate that the given factory has been closed.
    void sessionFactoryClosed(SessionFactory factory);
    ///Callback to indicate that the given factory has been created and is now ready for use.
    void sessionFactoryCreated(SessionFactory factory);
}

interface EventListeners {
    // TODO:
}

interface ConnectionProvider {
}

interface Settings {
    Dialect getDialect();
    ConnectionProvider getConnectionProvider();
    bool isAutoCreateSchema();
}

interface Mapping {
    string getIdentifierPropertyName(string className);
    Type getIdentifierType(string className);
    Type getReferencedPropertyType(string className, string propertyName);
}

class Configuration {
    bool dummy;
}

interface SessionFactory {
    void close();
    bool isClosed();
    Session openSession();
}

class SessionImpl : Session {

    private bool closed;
    SessionFactoryImpl sessionFactory;
    private EntityMetaData metaData;
    Dialect dialect;
    DataSource connectionPool;
    Connection conn;

    private void checkClosed() {
        enforceEx!HibernatedException(!closed, "Session is closed");
    }

    this(SessionFactoryImpl sessionFactory, EntityMetaData metaData, Dialect dialect, DataSource connectionPool) {
        this.sessionFactory = sessionFactory;
        this.metaData = metaData;
        this.dialect = dialect;
        this.connectionPool = connectionPool;
        this.conn = connectionPool.getConnection();
    }

    override Transaction beginTransaction() {
        throw new HibernatedException("Method not implemented");
    }
    override void cancelQuery() {
        throw new HibernatedException("Method not implemented");
    }
    override void clear() {
        throw new HibernatedException("Method not implemented");
    }
    ///Does this session contain any changes which must be synchronized with the database? In other words, would any DML operations be executed if we flushed this session?
    override bool isDirty() {
        throw new HibernatedException("Method not implemented");
    }
    /// Check if the session is still open.
    override bool isOpen() {
        return !closed;
    }
    /// Check if the session is currently connected.
    override bool isConnected() {
        return !closed;
    }
    /// End the session by releasing the JDBC connection and cleaning up.
    override Connection close() {
        checkClosed();
        closed = true;
        sessionFactory.sessionClosed(this);
        conn.close();
        return null;
    }
    ///Check if this instance is associated with this Session
    override bool contains(Object object) {
        throw new HibernatedException("Method not implemented");
    }
    override SessionFactory getSessionFactory() {
        checkClosed();
        return sessionFactory;
    }
    override string getEntityName(Object object) {
        checkClosed();
        return metaData.findEntityForObject(object).name;
    }
    
    override Object get(string entityName, Variant id) {
        EntityInfo info = metaData.findEntity(entityName);
        string query = metaData.generateFindByPkForEntity(info);
        //writeln("Finder query: " ~ query);
        PreparedStatement stmt = conn.prepareStatement(query);
        scope(exit) stmt.close();
        stmt.setVariant(1, id);
        ResultSet rs = stmt.executeQuery();
        //writeln("returned rows: " ~ to!string(rs.getFetchSize()));
        scope(exit) rs.close();
        if (rs.next()) {
            Object obj = info.createEntity();
            //writeln("reading columns");
            metaData.readAllColumns(obj, rs, 1);
            //writeln("value: " ~ obj.toString);
            return obj;
        } else {
            // not found!
            return null;
        }
    }

    /// Read the persistent state associated with the given identifier into the given transient instance.
    override Object load(string entityName, Variant id) {
        Object obj = get(entityName, id);
        enforceEx!HibernatedException(obj !is null, "Entity " ~ entityName ~ " with id " ~ to!string(id) ~ " not found");
        return obj;
    }

    /// Read the persistent state associated with the given identifier into the given transient instance
    override void load(Object obj, Variant id) {
        EntityInfo info = metaData.findEntityForObject(obj);
        string query = metaData.generateFindByPkForEntity(info);
        //writeln("Finder query: " ~ query);
        PreparedStatement stmt = conn.prepareStatement(query);
        scope(exit) stmt.close();
        stmt.setVariant(1, id);
        ResultSet rs = stmt.executeQuery();
        //writeln("returned rows: " ~ to!string(rs.getFetchSize()));
        scope(exit) rs.close();
        if (rs.next()) {
            //writeln("reading columns");
            metaData.readAllColumns(obj, rs, 1);
            //writeln("value: " ~ obj.toString);
        } else {
            // not found!
            enforceEx!HibernatedException(false, "Entity " ~ info.name ~ " with id " ~ to!string(id) ~ " not found");
        }
    }

    /// Re-read the state of the given instance from the underlying database.
    override void refresh(Object obj) {
        EntityInfo info = metaData.findEntityForObject(obj);
        string query = metaData.generateFindByPkForEntity(info);
        enforceEx!HibernatedException(info.isKeySet(obj), "Cannot refresh entity " ~ info.name ~ ": no Id specified");
        Variant id = info.getKey(obj);
        //writeln("Finder query: " ~ query);
        PreparedStatement stmt = conn.prepareStatement(query);
        scope(exit) stmt.close();
        stmt.setVariant(1, id);
        ResultSet rs = stmt.executeQuery();
        //writeln("returned rows: " ~ to!string(rs.getFetchSize()));
        scope(exit) rs.close();
        if (rs.next()) {
            //writeln("reading columns");
            metaData.readAllColumns(obj, rs, 1);
            //writeln("value: " ~ obj.toString);
        } else {
            // not found!
            enforceEx!HibernatedException(false, "Entity " ~ info.name ~ " with id " ~ to!string(id) ~ " not found");
        }
    }

    /// Persist the given transient instance, first assigning a generated identifier.
    override Object save(Object obj) {
        EntityInfo info = metaData.findEntityForObject(obj);
        bool generatedKey = false;
        if (!info.isKeySet(obj)) {
            if (info.getKeyProperty().generated) {
                generatedKey = true;
                throw new HibernatedException("Key is not set, but generated values are not supported so far");
            } else {
                throw new HibernatedException("Key is not set and no generator is specified");
            }
        } else {
            return obj;
        }
    }

    override string update(Object object) {
        throw new HibernatedException("Method not implemented");
    }

    // renamed from Session.delete since delete is D keyword
    override void remove(Object object) {
        throw new HibernatedException("Method not implemented");
    }
}

class SessionFactoryImpl : SessionFactory {
//    Configuration cfg;
//    Mapping mapping;
//    Settings settings;
//    EventListeners listeners;
//    SessionFactoryObserver observer;
    private bool closed;
    private EntityMetaData metaData;
    Dialect dialect;
    DataSource connectionPool;

    SessionImpl[] activeSessions;

    void sessionClosed(SessionImpl session) {
        foreach(i, item; activeSessions) {
            if (item == session) {
                remove(activeSessions, i);
            }
        }
    }

    this(EntityMetaData metaData, Dialect dialect, DataSource connectionPool) {
        this.metaData = metaData;
        this.dialect = dialect;
        this.connectionPool = connectionPool;
    }

//    this(Configuration cfg, Mapping mapping, Settings settings, EventListeners listeners, SessionFactoryObserver observer) {
//        this.cfg = cfg;
//        this.mapping = mapping;
//        this.settings = settings;
//        this.listeners = listeners;
//        this.observer = observer;
//        if (observer !is null)
//            observer.sessionFactoryCreated(this);
//    }
    private void checkClosed() {
        enforceEx!HibernatedException(!closed, "Session factory is closed");
    }
    override void close() {
        checkClosed();
        closed = true;
//        if (observer !is null)
//            observer.sessionFactoryClosed(this);
        // TODO:
    }
    bool isClosed() {
        return closed;
    }
    Session openSession() {
        checkClosed();
        SessionImpl session = new SessionImpl(this, metaData, dialect, connectionPool);
        activeSessions ~= session;
        return session;
    }
}
