/**
 * HibernateD - Object-Relation Mapping for D programming language, with interface similar to Hibernate.
 *
 * Hibernate documentation can be found here:
 * $(LINK http://hibernate.org/docs)$(BR)
 *
 * Source file hibernated/session.d.
 *
 * This module contains implementation of Hibernated SessionFactory and Session classes.
 *
 * Copyright: Copyright 2013
 * License:   $(LINK www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Author:   Vadim Lopatin
 */
module hibernated.session;

private import std.algorithm;
private import std.conv;
//private import std.stdio : writeln;
private import std.exception;
private import std.variant;
private import std.traits : isCallable;
//private import std.logger;

private import ddbc.core : Connection, DataSource, DataSetReader, DataSetWriter, PreparedStatement, ResultSet, Statement;

import hibernated.type;
import hibernated.dialect : Dialect;
import hibernated.core;
import hibernated.metadata;
import hibernated.query;

// For backwards compatibily
// 'enforceEx' will be removed with 2.089
static if(__VERSION__ < 2080) {
    alias enforceHelper = enforceEx;
} else {
    alias enforceHelper = enforce;
}

// For backwards compatibily (since D 2.101, logger is no longer in std.experimental)
static if (__traits(compiles, (){ import std.logger; } )) {
    pragma(msg, "Hibernated will log using 'std.logger'.");
    import std.logger : trace, warning;
} else {
    pragma(msg, "Hibernated will log using 'std.experimental.logger'.");
    import std.experimental.logger : trace, warning;
}

/**
 * Factory to create HibernateD Sessions - similar to org.hibernate.SessionFactory
 *
 * See_Also: https://docs.jboss.org/hibernate/stable/orm/javadocs/org/hibernate/SessionFactory.html
 */
interface SessionFactory {
    /// close all active sessions
	void close();
    /// check if session factory is closed
	bool isClosed();
    /// creates new session
	Session openSession();
    /// retrieve information about tables and indexes for schema
    DBInfo getDBMetaData();
}

/**
 * Session - main interface to load and persist entities -- similar to org.hibernate.Session
 *
 * See_Also: https://docs.jboss.org/hibernate/stable/orm/javadocs/org/hibernate/Session.html
 */
abstract class Session
{
    /// returns metadata
    EntityMetaData getMetaData();

	/**
	 * Begins a new DB transaction, causing all statements run to complete together or not at all.
	 *
	 * All statements will attempt to be applied when returned Transaction object's `commit()`
	 * method is called, or discarded if the `rollback()` method is called.
	 */
	Transaction beginTransaction();

	/// not supported in current implementation
	void cancelQuery();

	/// Evicts all entities from the session's cache: later loads read them from the database again. Rolling a
	/// transaction back does it too.
	void clear();

	/// Closes the session.
	/// All sessions that are not explicitly closed will be closed when the connection is closed.
	Connection close();

    ///Does this session contain any changes which must be synchronized with the database? In other words, would any DML operations be executed if we flushed this session?
    bool isDirty();
    /// Check if the session is still open.
    bool isOpen();
    /// Check if the session is currently connected.
    bool isConnected();
    /// Check if this instance is associated with this Session.
    bool contains(Object object);
    /// Retrieve session factory used to create this session
	SessionFactory getSessionFactory();
    /// Lookup metadata to find entity name for object.
	string getEntityName(Object object);
    /// Lookup metadata to find entity name for class type info.
    string getEntityName(TypeInfo_Class type);

    /// Return the persistent instance of the given named entity with the given identifier, or null if there is no such persistent instance.
    T get(T : Object, ID)(ID id) {
        Variant v = id;
        return cast(T)getObject(getEntityName(T.classinfo), v);
    }

    /// Read the persistent state associated with the given identifier into the given transient instance.
    T load(T : Object, ID)(ID id) {
        Variant v = id;
        return cast(T)loadObject(getEntityName(T.classinfo), v);
    }

    /// Read the persistent state associated with the given identifier into the given transient instance.
    void load(T : Object, ID)(T obj, ID id) {
        Variant v = id;
        loadObject(obj, v);
    }

    /// Return the persistent instance of the given named entity with the given identifier, or null if there is no such persistent instance.
	Object getObject(string entityName, Variant id);

    /// Read the persistent state associated with the given identifier into the given transient instance.
    Object loadObject(string entityName, Variant id);

    /// Read the persistent state associated with the given identifier into the given transient instance
    void loadObject(Object obj, Variant id);

    /// Re-read the state of the given instance from the underlying database.
	void refresh(Object obj);

    /// Persist the given transient instance, first assigning a generated identifier.
	Variant save(Object obj);

	/// Persist the given transient instance.
	void persist(Object obj);

	/// Update the persistent instance with the identifier of the given detached instance.
	void update(Object object);

    /// remove object from DB (renamed from original Session.delete - it's keyword in D)
    void remove(Object object);

	/// Create a new instance of Query for the given HQL query string
	Query createQuery(string queryString);

    /// Execute a discrete piece of work using the supplied connection.
    void doWork(void delegate(Connection) func);

    // Templates are implicifly final, thus, we need to write the type explicitly.
    //void doWork(F)(F func)
    //if (isCallable!func && is(typeof(func(Connection.__init__)) == void));
}

/**
 * Represents a transaction under the controll of HibernateD. Every transaction is associated with a
 * [Session] and begins with an explicit call to [Session.beginTransaction()], or with
 * `session.getTransaction().begin()`, and ends with a call to [commit()] or [rollback()].
 *
 * A single session may be associated with multiple transactions, however, there is only one
 * uncommitted transaction associated with a given [Session] at a time.
 *
 * If shared, a [Transaction] object is not threadsafe.
 *
 * See_Also:
 *   https://docs.jboss.org/hibernate/stable/orm/javadocs/org/hibernate/Transaction.html
 *   https://jakarta.ee/specifications/platform/9/apidocs/jakarta/persistence/entitytransaction
 */
interface Transaction {
  /**
   * Start a transaction managed by HibernateD.
   *
   * Throws:
   * - IllegalStateException if `isActive()` is true.
   */
  void begin();

  /**
   * Commit the current resource transaction, writing any unflushed changes to the database.
   *
   * If the commit fails, the transaction stays active: call `rollback()` (which ends it also when it fails).
   *
   * Throws:
   * - IllegalStateException if `isActive()` is false
   * - RollbackException if the commit fails
   */
  void commit();

  /**
   * Indicates whether a transaction is currently in progress.
   */
  bool isActive();

  /**
   * Roll back the currently active transaction.
   *
   * Throws:
   * - IllegalStateException if `isActive()` is false
   * - PersistenceException if an unexpected error condition is encountered
   */
  void rollback();
}

class TransactionImpl : Transaction {
    Session session;

    enum Status {
        INACTIVE,
        ACTIVE,
    }
    Status status = Status.INACTIVE;
    /// The connection's auto-commit mode before `begin`, restored by `commit` and `rollback`.
    private bool autoCommitBefore = true;

    this(Session session) {
        this.session = session;
    }

    override
    void begin() {
        if (!session.isOpen()) {
            throw new HibernatedException("Cannot begin Transaction on closed Session.");
        }
        if (isActive()) {
            throw new HibernatedException("Transaction is already active.");
        }
        if (auto impl = cast(SessionImpl) session) {
            if (!impl.dialect.supportsTransactions())
                throw new HibernatedException("Transactions are not supported by this database");
        }
        session.doWork((conn) {
            autoCommitBefore = conn.getAutoCommit();
            conn.setAutoCommit(false);
            status = Status.ACTIVE;
        });
    }

    override
    void commit() {
        if (!session.isOpen()) {
            throw new HibernatedException("Cannot commit Transaction on closed Session.");
        }
        if (!isActive()) {
            throw new HibernatedException("Cannot commit inactive Transaction.");
        }
        session.doWork((conn) {
            conn.commit();
            status = Status.INACTIVE;
            // Later work in this session must not run in an implicit transaction, which
            // the connection pool rolls back when the session closes
            conn.setAutoCommit(autoCommitBefore);
        });
    }

    override
    bool isActive() {
        return status == Status.ACTIVE;
    }

    /++
    Rolls the transaction back. It is over afterwards also when the rollback fails (e.g. the connection is lost,
    and with it the transaction): `isActive` is false and `begin` works again (#135). The session's cache is
    cleared (`Session.clear`): its entities may hold state the rollback undid. Objects saved in the transaction
    keep their generated keys; save new objects (or use a new session) when retrying. If restoring the connection's
    auto-commit mode fails after a successful rollback, the exception says so, and later work in the session would
    run in an implicit transaction: close the session then.
    +/
    override
    void rollback() {
        if (!session.isOpen()) {
            throw new HibernatedException("Cannot roll back Transaction on closed Session.");
        }
        if (!isActive()) {
            throw new HibernatedException("Cannot roll back inactive Transaction.");
        }
        scope (exit) {
            status = Status.INACTIVE;
            // the cache directly: nothing may throw here while a rollback error unwinds (LDC aborts on that)
            if (auto impl = cast(SessionImpl) session)
                impl.cache = null;
        }
        session.doWork((conn) {
            // not in a scope(exit): a second exception thrown while the first unwinds aborted LDC's unwinder
            try
                conn.rollback();
            catch (Exception e) {
                collectException(conn.setAutoCommit(autoCommitBefore)); // the rollback's error matters
                throw e;
            }
            conn.setAutoCommit(autoCommitBefore);
        });
    }
}

/// Interface for usage of HQL queries.
abstract class Query
{
	///Get the query string.
	string 	getQueryString();
	/// Convenience method to return a single instance that matches the query, or null if the query returns no results.
	Object 	uniqueObject();
    /// Convenience method to return a single instance that matches the query, or null if the query returns no results. Reusing existing buffer.
    Object  uniqueObject(Object obj);
    /// Convenience method to return a single instance that matches the query, or null if the query returns no results.
    T uniqueResult(T : Object)() {
        return cast(T)uniqueObject();
    }
    /// Convenience method to return a single instance that matches the query, or null if the query returns no results. Reusing existing buffer.
    T uniqueResult(T : Object)(T obj) {
        return cast(T)uniqueObject(obj);
    }

    /// Convenience method to return a single instance that matches the query, or null if the query returns no results.
	Variant[] uniqueRow();
	/// Return the query results as a List of entity objects
	Object[] listObjects();
    /// Return the query results as a List of entity objects
    T[] list(T : Object)() {
        return cast(T[])listObjects();
    }
    /// Return the query results as a List which each row as Variant array
	Variant[][] listRows();

	/// Bind a value to a named query parameter (all :parameters used in query should be bound before executing query).
	protected Query setParameterVariant(string name, Variant val);

    /// Bind a value to a named query parameter (all :parameters used in query should be bound before executing query).
    Query setParameter(T)(string name, T val) {
        static if (is(T == Variant)) {
            return setParameterVariant(name, val);
        } else {
            return setParameterVariant(name, Variant(val));
        }
    }
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

class EntityCache {
    const string name;
    const EntityInfo entity;
    Object[Variant] items;
    this(const EntityInfo entity) {
        this.entity = entity;
        this.name = entity.name;
    }
    bool hasKey(Variant key) {
        return ((key in items) !is null);
    }
    Object peek(Variant key) {
        if ((key in items) is null)
            return null;
        return items[key];
    }
    Object get(Variant key) {
        enforceHelper!CacheException((key in items) !is null, "entity " ~ name ~ " with key " ~ key.toString() ~ " not found in cache");
        return items[key];
    }
    void put(Variant key, Object obj) {
        items[key] = obj;
    }
    Object[] lookup(Variant[] keys, out Variant[] unknownKeys) {
        Variant[] unknown;
        Object[] res;
        foreach(key; keys) {
            Object obj = peek(normalize(key));
            if (obj !is null) {
                res ~= obj;
            } else {
                unknown ~= normalize(key);
            }
        }
        unknownKeys = unknown;
        return res;
    }
}

/// helper class to disconnect Lazy loaders from closed session.
class SessionAccessor {
    private SessionImpl _session;

    this(SessionImpl session) {
        _session = session;
    }
    /// returns session, with session state check - throws LazyInitializationException if attempting to get unfetched lazy data while session is closed
    SessionImpl get() {
        enforceHelper!LazyInitializationException(_session !is null, "Cannot read from closed session");
        return _session;
    }
    /// nulls session reference
    void onSessionClosed() {
        _session = null;
    }
}

/// Implementation of HibernateD session
class SessionImpl : Session {

    private bool closed;
    SessionFactoryImpl sessionFactory;
    private EntityMetaData metaData;
    Dialect dialect;
    DataSource connectionPool;
    Connection conn;
    Transaction currentTransaction;

    EntityCache[string] cache;

    private SessionAccessor _accessor;
    @property SessionAccessor accessor() {
        return _accessor;
    }

    package EntityCache getCache(string entityName) {
        EntityCache res;
        if ((entityName in cache) is null) {
            res = new EntityCache(metaData[entityName]);
            cache[entityName] = res;
        } else {
            res = cache[entityName];
        }
        return res;
    }

    package bool keyInCache(string entityName, Variant key) {
        return getCache(entityName).hasKey(normalize(key));
    }

    package Object peekFromCache(string entityName, Variant key) {
        return getCache(entityName).peek(normalize(key));
    }

    package Object getFromCache(string entityName, Variant key) {
        return getCache(entityName).get(normalize(key));
    }

    package void putToCache(string entityName, Variant key, Object value) {
        return getCache(entityName).put(normalize(key), value);
    }

    package Object[] lookupCache(string entityName, Variant[] keys, out Variant[] unknownKeys) {
        return getCache(entityName).lookup(keys, unknownKeys);
    }

    override EntityMetaData getMetaData() {
        return metaData;
    }

    private void checkClosed() {
        enforceHelper!SessionException(!closed, "Session is closed");
    }

    this(SessionFactoryImpl sessionFactory, EntityMetaData metaData, Dialect dialect, DataSource connectionPool) {
        trace("Creating session");
        this.sessionFactory = sessionFactory;
        this.metaData = metaData;
        this.dialect = dialect;
        this.connectionPool = connectionPool;
        this.conn = connectionPool.getConnection();
        this._accessor = new SessionAccessor(this);
    }

    override Transaction beginTransaction() {
        // See: hibernate/internal/AbstractSharedSessionContract.accessTransaction()
        checkClosed();
        if (currentTransaction is null) {
            currentTransaction = new TransactionImpl(this);
        }
        currentTransaction.begin();
        return currentTransaction;
    }
    override void cancelQuery() {
        throw new HibernatedException("Method not implemented");
    }
    /// Evicts all entities from the session's cache: later loads read them from the database again.
    override void clear() {
        checkClosed();
        cache = null;
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
    /++
    End the session by releasing the JDBC connection and cleaning up. An active transaction is rolled back first:
    closing the connection would commit it on some databases (Oracle's logoff does), #135.
    +/
    override Connection close() {
        checkClosed();
        if (currentTransaction !is null && currentTransaction.isActive()) {
            if (auto e = collectException(currentTransaction.rollback())) // the session closes anyway
                warning("Rolling back the active transaction while closing the session failed: " ~ e.msg);
        }
        _accessor.onSessionClosed();
        closed = true;
        sessionFactory.sessionClosed(this);
        trace("closing connection");
        assert(conn !is null);
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

    override string getEntityName(TypeInfo_Class type) {
        checkClosed();
        return metaData.getEntityName(type);
    }

    override Object getObject(string entityName, Variant id) {
        auto info = metaData.findEntity(entityName);
        return getObject(info, null, id);
    }

    /// Read the persistent state associated with the given identifier into the given transient instance.
    override Object loadObject(string entityName, Variant id) {
        Object obj = getObject(entityName, id);
        enforceHelper!ObjectNotFoundException(obj !is null, "Entity " ~ entityName ~ " with id " ~ to!string(id) ~ " not found");
        return obj;
    }

    /// Read the persistent state associated with the given identifier into the given transient instance
    override void loadObject(Object obj, Variant id) {
        auto info = metaData.findEntityForObject(obj);
        Object found = getObject(info, obj, id);
        enforceHelper!ObjectNotFoundException(found !is null, "Entity " ~ info.name ~ " with id " ~ to!string(id) ~ " not found");
    }

    /// Read the persistent state associated with the given identifier into the given transient instance
    Object getObject(const EntityInfo info, Object obj, Variant id) {
        if (info.getKeyProperty().relation == RelationType.Embedded) {
            auto embeddedEntityInfo = info.getKeyProperty().referencedEntity;
            string hql = "FROM " ~ info.name ~ " WHERE ";
            bool isFirst = true;
            foreach (propertyInfo; embeddedEntityInfo) {
                if (isFirst) {
                    isFirst = false;
                } else {
                    hql ~= " AND ";
                }
                hql ~= info.getKeyProperty().propertyName ~ "." ~ propertyInfo.propertyName ~ "=:" ~ propertyInfo.propertyName;
            }
            Query q = createQuery(hql);
            foreach (propertyInfo; embeddedEntityInfo) {
                q = q.setParameter(
                        propertyInfo.propertyName,
                        embeddedEntityInfo.getPropertyValue(id.get!Object, propertyInfo.propertyName));
            }
            Object res = q.uniqueResult(obj);
            return res;
        } else {
            string hql = "FROM " ~ info.name ~ " WHERE " ~ info.getKeyProperty().propertyName ~ "=:Id";
            Query q = createQuery(hql).setParameter("Id", id);
            Object res = q.uniqueResult(obj);
            return res;
        }
    }

    /// Read entities referenced by property
    Object[] loadReferencedObjects(const EntityInfo info, string referencePropertyName, Variant fk) {
        string hql = "SELECT a2 FROM " ~ info.name ~ " AS a1 JOIN a1." ~ referencePropertyName ~ " AS a2 WHERE a1." ~ info.getKeyProperty().propertyName ~ "=:Fk";
        Query q = createQuery(hql).setParameter("Fk", fk);
        Object[] res = q.listObjects();
        return res;
    }

    /// Re-read the state of the given instance from the underlying database.
    override void refresh(Object obj) {
        auto info = metaData.findEntityForObject(obj);
        string query = metaData.generateFindByPkForEntity(dialect, info);
        enforceHelper!TransientObjectException(info.isKeySet(obj), "Cannot refresh entity " ~ info.name ~ ": no Id specified");
        Variant id = info.getKey(obj);
        trace("refresh query: " ~ query);
        PreparedStatement stmt = conn.prepareStatement(query);
        scope(exit) stmt.close();
        if (info.keyProperty.relation == RelationType.Embedded) {
            int pos = 1;
            foreach (pi; info.keyProperty.referencedEntity()) {
                stmt.setVariant(pos++, pi.getFunc(id.get!Object));
            }
        } else {
            stmt.setVariant(1, id);
        }
        ResultSet rs = stmt.executeQuery();
        //trace("returned rows: " ~ to!string(rs.getFetchSize()));
        scope(exit) rs.close();
        if (rs.next()) {
            //trace("reading columns");
            metaData.readAllColumns(obj, rs, 1);
            //trace("value: " ~ obj.toString);
        } else {
            // not found!
            enforceHelper!ObjectNotFoundException(false, "Entity " ~ info.name ~ " with id " ~ to!string(id) ~ " not found");
        }
    }

    private void saveRelations(const EntityInfo ei, Object obj) {
        foreach(p; ei) {
            if (p.manyToMany) {
                saveRelations(p, obj);
            }
        }
    }

    private void saveRelations(const PropertyInfo p, Object obj) {
        Object[] relations = p.getCollectionFunc(obj);
        Variant thisId = p.entity.getKey(obj);
        if (relations !is null && relations.length > 0) {
            Variant[] otherIds;
            foreach(r; relations)
                otherIds ~= p.referencedEntity.getKey(r);
            insertRelationRows(p, thisId, otherIds);
        }
    }

    // The keys of join-table rows are bound as parameters, not written into the SQL: the driver then writes them
    // as it writes the entity's own key column (dates in the stored form, strings without any escaping), #122.
    // Statements bind at most about 900 parameters: SQLite before 3.32 allows 999 per statement.
    private enum maxRelationParameters = 900;

    private void insertRelationRows(const PropertyInfo p, Variant thisId, Variant[] otherIds) {
        import std.range : chunks;
        foreach (chunk; otherIds.chunks(maxRelationParameters / 2)) {
            PreparedStatement stmt = conn.prepareStatement(p.joinTable.getInsertSQL(dialect, chunk.length));
            scope(exit) stmt.close();
            int index = 1;
            foreach (otherId; chunk) {
                stmt.setVariant(index++, thisId);
                stmt.setVariant(index++, otherId);
            }
            stmt.executeUpdate();
        }
    }

    private void deleteRelationRows(const PropertyInfo p, Variant thisId, Variant[] otherIds) {
        import std.range : chunks;
        foreach (chunk; otherIds.chunks(maxRelationParameters - 1)) {
            PreparedStatement stmt = conn.prepareStatement(p.joinTable.getDeleteSQL(dialect, chunk.length));
            scope(exit) stmt.close();
            stmt.setVariant(1, thisId);
            int index = 2;
            foreach (otherId; chunk)
                stmt.setVariant(index++, otherId);
            stmt.executeUpdate();
        }
    }

    private void updateRelations(const EntityInfo ei, Object obj) {
        foreach(p; ei) {
            if (p.manyToMany) {
                updateRelations(p, obj);
            }
        }
    }

    private void deleteRelations(const EntityInfo ei, Object obj) {
        foreach(p; ei) {
            if (p.manyToMany) {
                deleteRelations(p, obj);
            }
        }
    }

    private Variant[] readRelationIds(const PropertyInfo p, Variant thisId) {
        Variant[] res;
        PreparedStatement stmt = conn.prepareStatement(p.joinTable.getOtherKeySelectSQL(dialect));
        scope(exit) stmt.close();
        stmt.setVariant(1, thisId);
        ResultSet rs = stmt.executeQuery();
        scope(exit) rs.close();
        while (rs.next()) {
            res ~= rs.getVariant(1);
        }
        return res;
    }

    private void updateRelations(const PropertyInfo p, Object obj) {
        Variant thisId = p.entity.getKey(obj);
        Variant[] oldRelIds = readRelationIds(p, thisId);
        Variant[] newRelIds = p.getCollectionIds(obj);
        // Keys are compared by their text: the ones read back may have another type than the entity's key
        // (an int for a long, a SQLite date as text).
        Variant[string] oldmap;
        foreach(v; oldRelIds)
            oldmap[keyText(v)] = v;
        Variant[string] newmap;
        foreach(v; newRelIds)
            newmap[keyText(v)] = v;
        Variant[] keysToDelete;
        Variant[] keysToAdd;
        foreach(k, v; newmap)
            if ((k in oldmap) is null)
                keysToAdd ~= v;
        foreach(k, v; oldmap)
            if ((k in newmap) is null)
                keysToDelete ~= v;
        // Delete first: if a key reads back in a form keyText doesn't match, its row is deleted and inserted again;
        // inserting first would insert it twice and then delete both, losing the relation on every update. The cost:
        // without a transaction (always on ClickHouse), a failing insert leaves the removed relations deleted.
        if (keysToDelete.length > 0)
            deleteRelationRows(p, thisId, keysToDelete);
        if (keysToAdd.length > 0)
            insertRelationRows(p, thisId, keysToAdd);
    }

    private void deleteRelations(const PropertyInfo p, Object obj) {
        Variant thisId = p.entity.getKey(obj);
        // only when there are rows: a DELETE is a mutation on ClickHouse, much more expensive than the SELECT
        if (readRelationIds(p, thisId).length == 0)
            return;
        PreparedStatement stmt = conn.prepareStatement(p.joinTable.getDeleteAllSQL(dialect));
        scope(exit) stmt.close();
        stmt.setVariant(1, thisId);
        stmt.executeUpdate();
    }


    /// Persist the given transient instance, first assigning a generated identifier if not assigned; returns generated value
    override Variant save(Object obj) {
        auto info = metaData.findEntityForObject(obj);
        if (!info.isKeySet(obj)) {
            if (info.getKeyProperty().generated && !dialect.supportsGeneratedKeys()) {
                // the database cannot generate keys: the dialect generates it before the insert
                Variant generatedKey = dialect.generateKey(conn, info);
                enforceKeyGenerated(generatedKey, info, "The dialect generated no key");
                info.setKey(obj, generatedKey);
                string query = metaData.generateInsertAllFieldsForEntity(obj, dialect, info);
                PreparedStatement stmt = conn.prepareStatement(query);
                scope(exit) stmt.close();
                metaData.writeAllColumns(obj, stmt, 1);
                stmt.executeUpdate();
            } else if (info.getKeyProperty().generated) {
                // autogenerated on DB side
                string query = dialect.appendInsertToFetchGeneratedKey(metaData.generateInsertNoKeyForEntity(obj, dialect, info), info);
				PreparedStatement stmt = conn.prepareStatement(query);
				scope(exit) stmt.close();
				metaData.writeAllColumns(obj, stmt, 1, true);
				Variant generatedKey;
				stmt.executeUpdate(generatedKey);
				enforceKeyGenerated(generatedKey, info, "The database returned no generated key (the row was inserted)");
			    info.setKey(obj, generatedKey);
            } else if (info.getKeyProperty().generatorFunc !is null) {
                // has generator function
                Variant generatedKey = info.getKeyProperty().generatorFunc(conn, info.getKeyProperty());
                enforceKeyGenerated(generatedKey, info, "The key generator returned no key");
                info.setKey(obj, generatedKey);
                string query = metaData.generateInsertAllFieldsForEntity(obj, dialect, info);
                PreparedStatement stmt = conn.prepareStatement(query);
                scope(exit) stmt.close();
                metaData.writeAllColumns(obj, stmt, 1);
                stmt.executeUpdate();
            } else {
                throw new PropertyValueException("Key is not set and no generator is specified");
            }
        } else {
			string query = metaData.generateInsertAllFieldsForEntity(obj, dialect, info);
			PreparedStatement stmt = conn.prepareStatement(query);
			scope(exit) stmt.close();
			metaData.writeAllColumns(obj, stmt, 1);
			stmt.executeUpdate();
        }
        Variant key = info.getKey(obj);
        putToCache(info.name, key, obj);
        saveRelations(info, obj);
        return key;
    }

	/// Persist the given transient instance.
	override void persist(Object obj) {
        auto info = metaData.findEntityForObject(obj);
        enforceHelper!TransientObjectException(info.isKeySet(obj), "Cannot persist entity w/o key assigned");
		string query = metaData.generateInsertAllFieldsForEntity(obj, dialect, info);
		PreparedStatement stmt = conn.prepareStatement(query);
		scope(exit) stmt.close();
		metaData.writeAllColumns(obj, stmt, 1);
		stmt.executeUpdate();
        Variant key = info.getKey(obj);
        putToCache(info.name, key, obj);
        saveRelations(info, obj);
    }

    override void update(Object obj) {
        auto info = metaData.findEntityForObject(obj);
        enforceHelper!TransientObjectException(info.isKeySet(obj), "Cannot persist entity w/o key assigned");
        string query = metaData.generateUpdateForEntity(obj, dialect, info);
        //trace("Query: " ~ query);
        {
            PreparedStatement stmt = conn.prepareStatement(query);
            scope(exit) stmt.close();
            int columnCount = metaData.writeAllColumns(obj, stmt, 1, true);
            if (info.keyProperty.relation == RelationType.Embedded) {
                metaData.writeAllColumns(info.getKey(obj).get!Object, stmt, columnCount + 1, false);
            } else {
                info.keyProperty.writeFunc(obj, stmt, columnCount + 1);
            }
            stmt.executeUpdate();
        }
        updateRelations(info, obj);
    }

    // renamed from Session.delete since delete is D keyword
    override void remove(Object obj) {
        auto info = metaData.findEntityForObject(obj);
        deleteRelations(info, obj);
        string query = "DELETE FROM " ~ dialect.quoteIfNeeded(info.tableName) ~ " WHERE ";
        if (info.keyProperty.relation == RelationType.Embedded) {
            auto embeddedEntityInfo = info.getKeyProperty().referencedEntity;
            bool isFirst = true;
            foreach (propertyInfo; embeddedEntityInfo) {
                if (isFirst) {
                    isFirst = false;
                } else {
                    query ~= " AND ";
                }
                query ~= dialect.quoteIfNeeded(propertyInfo.columnName) ~ "=?";
            }
        } else {
            query ~= dialect.quoteIfNeeded(info.getKeyProperty().columnName) ~ "=?";
        }
		PreparedStatement stmt = conn.prepareStatement(query);
        if (info.keyProperty.relation == RelationType.Embedded) {
            metaData.writeAllColumns(info.getKey(obj).get!Object, stmt, 1, false);
        } else {
            info.getKeyProperty().writeFunc(obj, stmt, 1);
        }
		stmt.executeUpdate();
	}

	/// Create a new instance of Query for the given HQL query string
	override Query createQuery(string queryString) {
		return new QueryImpl(this, queryString);
	}

    /// Execute a discrete piece of work using the supplied connection.
    override void doWork(void delegate(Connection) func) {
        func(conn);
    }
}

/// Implementation of HibernateD SessionFactory
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


    DBInfo _dbInfo;
    override public DBInfo getDBMetaData() {
        if (_dbInfo is null)
            _dbInfo = new DBInfo(dialect, metaData);
        return _dbInfo;
    }


    void sessionClosed(SessionImpl session) {
        foreach(i, item; activeSessions) {
            if (item == session) {
                activeSessions = remove(activeSessions, i);
            }
        }
    }

    this(EntityMetaData metaData, Dialect dialect, DataSource connectionPool) {
        trace("Creating session factory");
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
        enforceHelper!SessionException(!closed, "Session factory is closed");
    }

	override void close() {
        trace("Closing session factory");
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

struct ObjectList {
    Object[] list;
    void add(Object obj) {
        foreach(v; list) {
            if (v == obj) {
                return; // avoid duplicates
            }
        }
        list ~= obj;
    }
    @property int length() { return cast(int)list.length; }
    ref Object opIndex(size_t index) {
        return list[index];
    }
}

Variant normalize(Variant v) {
    // variants of different type are not equal, normalize to make sure that keys Variant(1) and Variant(1L) are the same
    if (v.type == typeid(ulong) && v.get!ulong > long.max)
        return v; // convertsTo!long is true for a ulong too, and get!long would make it negative (#119)
    if (v.convertsTo!long)
        return Variant(v.get!long);
    else if (v.convertsTo!ulong)
        return Variant(v.get!ulong);
    else if (v.convertsTo!Object) {
        // Warning: Objects need to define `bool opEquals(...)` to make this reliable.
        return Variant(v.get!Object);
    }
    return Variant(keyText(v)); // dates as the text SQLite returns for them (#122)
}

/// task to load reference entity
class PropertyLoadItem {
    const PropertyInfo property;
    private ObjectList[Variant] _map; // ID to object list
    this(const PropertyInfo property) {
        this.property = property;
    }
    @property ref ObjectList[Variant] map() { return _map; }
    @property Variant[] keys() { return _map.keys; }
    @property int length() { return cast(int)_map.length; }
    ObjectList * opIndex(Variant key) {
        Variant id = normalize(key);
        if ((id in _map) is null) {
            _map[id] = ObjectList();
        }
        //assert(length > 0);
        return &_map[id];
    }
    void add(ref Variant id, Object obj) {
        auto item = opIndex(id);
        item.add(obj);
        //assert(item.length == opIndex(id).length);
    }
    string createCommaSeparatedKeyList() {
        assert(map.length > 0);
        return .createCommaSeparatedKeyList(map.keys);
    }
}

/// Throws `HibernatedException` (`what` ~ " for " ~ the entity's name) if `key` is null or empty: setting it would
/// make the key 0 or its type's default.
private void enforceKeyGenerated(Variant key, const EntityInfo info, string what) {
    if (isNullVariant(key))
        throw new HibernatedException(what ~ " for " ~ info.name);
}

/// The text of a key value: integers as digits, `Date`, `DateTime` and `TimeOfDay` in the ISO form that ddbc stores
/// and that every supported database reads (`YYYY-MM-DD`, `YYYY-MM-DD HH:MM:SS`, `HH:MM:SS`), anything else as
/// `toString`; `const` and `immutable` values too. A `SysTime` gives the `DateTime` text of its time in its own
/// timezone: ddbc's ClickHouse driver reads a `DateTime64(0)` column, which stores `DateTime` properties, as a
/// `SysTime` in the column timezone. On Windows clickhoused can't resolve that timezone and uses UTC, so with a
/// server in another timezone the text differs from the key's (a reference to an entity keyed by a `DateTime` isn't
/// found then). Before #122 dates used `toString` (`2019-Sep-15`), which matches no stored value.
package string keyText(Variant id) {
    import std.datetime : Date, DateTime, SysTime, TimeOfDay;
    import std.meta : AliasSeq;
    TypeInfo stored = id.type;
    auto qualified = cast(TypeInfo_Const) stored;
    if (qualified !is null)
        stored = qualified.base;
    static foreach (T; AliasSeq!(Date, DateTime, SysTime, TimeOfDay)) {
        if (stored == typeid(T)) {
            const T value = qualified is null ? id.get!T : id.get!(const T); // get!T refuses a stored const(T)
            static if (is(T == Date) || is(T == TimeOfDay))
                return value.toISOExtString();
            else {
                static if (is(T == SysTime))
                    const DateTime dt = cast(DateTime) value;
                else
                    alias dt = value;
                return dt.date.toISOExtString() ~ " " ~ dt.timeOfDay.toISOExtString();
            }
        }
    }
    return id.toString();
}

/// The key as an HQL literal: integers as digits, anything else as `keyText` in quotes, with `'` doubled (the SQL
/// standard form, which the HQL lexer reads; the dialect then quotes the value for its database). Not for SQL:
/// join-table statements bind the keys as parameters (#122).
string createKeySQL(Variant id) {
    import std.string : translate;
    if (id.convertsTo!long || id.convertsTo!ulong) {
        return id.toString();
    } else {
        // Quote (') in strings as ('') according to the SQL standard.
        return "'" ~ keyText(id).translate(['\'': "''"]) ~ "'";
    }
}

deprecated("Join-table keys are bound as parameters now (#122); a string key written by this breaks on MySQL and ClickHouse")
string createKeyPairSQL(Variant id1, Variant id2) {
    return "(" ~ createKeySQL(id1) ~ ", " ~ createKeySQL(id2) ~ ")";
}

string createCommaSeparatedKeyList(Variant[] list) {
    assert(list.length > 0);
    string res;
    foreach(v; list) {
        if (res.length > 0)
            res ~= ", ";
        res ~= createKeySQL(v);
    }
    return res;
}

/// task to load reference entity
class EntityCollections {
    private ObjectList[Variant] _map; // ID to object list
    @property ref ObjectList[Variant] map() { return _map; }
    @property Variant[] keys() { return _map.keys; }
    @property int length() { return cast(int)_map.length; }
    ref Object[] opIndex(Variant key) {
        //trace("searching for key " ~ key.toString);
        Variant id = normalize(key);
        if ((id in _map) is null) {
            //trace("creating new item");
            _map[id] = ObjectList();
        }
        //assert(length > 0);
        //trace("returning item");
        return _map[id].list;
    }
    void add(ref Variant id, Object obj) {
        auto item = opIndex(id);
        //trace("item count = " ~ to!string(item.length));
        item ~= obj;
    }
}

class PropertyLoadMap {
    private PropertyLoadItem[const PropertyInfo] _map;
    PropertyLoadItem opIndex(const PropertyInfo prop) {
        if ((prop in _map) is null) {
            //trace("creating new PropertyLoadItem for " ~ prop.propertyName);
            _map[prop] = new PropertyLoadItem(prop);
        }
        assert(_map.length > 0);
        return _map[prop];
    }

    this() {}

    this(PropertyLoadMap plm) {
        foreach(k; plm.keys) {
            auto pli = plm[k];
            foreach(plik; pli.map.keys) {
                foreach(obj; pli.map[plik].list.dup) {
                    add(k, plik, obj);
                }
            }
        }
    }

    PropertyLoadItem remove(const PropertyInfo pi) {
        PropertyLoadItem item = _map[pi];
        _map.remove(pi);
        return item;
    }
    @property ref PropertyLoadItem[const PropertyInfo] map() { return _map; }
    @property int length() { return cast(int)_map.length; }
    @property const (PropertyInfo)[] keys() { return _map.keys; }
    void add(const PropertyInfo property, Variant id, Object obj) {
        auto item = opIndex(property);
        item.add(id, obj);
        //assert(item.length > 0);
    }
}

/// Implementation of HibernateD Query
class QueryImpl : Query
{
	SessionImpl sess;
	ParsedQuery query;
	ParameterValues params;
	this(SessionImpl sess, string queryString) {
		this.sess = sess;
		//trace("QueryImpl(): HQL: " ~ queryString);
		QueryParser parser = new QueryParser(sess.metaData, queryString);
		//trace("parsing");
		this.query = parser.makeSQL(sess.dialect);
		//trace("SQL: " ~ this.query.sql);
		params = query.createParams();
		//trace("exiting QueryImpl()");
	}

	///Get the query string.
	override string getQueryString() {
		return query.hql;
	}

	/// Convenience method to return a single instance that matches the query, or null if the query returns no results.
	override Object uniqueObject() {
        return uniqueResult(cast(Object)null);
	}

    /// Convenience method to return a single instance that matches the query, or null if the query returns no results. Reusing existing buffer.
    override Object uniqueObject(Object obj) {
        Object[] rows = listObjects(obj);
        if (rows == null)
            return null;
        enforceHelper!NonUniqueResultException(rows.length == 1, "Query returned more than one object: " ~ getQueryString());
        return rows[0];
    }

	/// Convenience method to return a single instance that matches the query, or null if the query returns no results.
	override Variant[] uniqueRow() {
		Variant[][] rows = listRows();
		if (rows == null)
			return null;
        enforceHelper!NonUniqueResultException(rows.length == 1, "Query returned more than one row: " ~ getQueryString());
		return rows[0];
	}

    private FromClauseItem findRelation(FromClauseItem from, const PropertyInfo prop) {
        for (int i=0; i<query.from.length; i++) {
            FromClauseItem f = query.from[i];
            if (f.base == from && f.baseProperty == prop)
                return f;
            if (f.entity == prop.referencedEntity && from.base == f)
                return f;
        }
        return null;
    }

    private Object readRelations(Object objectContainer, DataSetReader r, PropertyLoadMap loadMap) {
        Object[] relations = new Object[query.select.length];
        //trace("select clause len = " ~ to!string(query.select.length));
        // read all related objects from DB row
        for (int i = 0; i < query.select.length; i++) {
            FromClauseItem from = query.select[i].from;
            //trace("reading " ~ from.entityName);
            Object row;
            if (!from.entity.isKeyNull(r, from.startColumn)) {
                //trace("key is not null");
                Variant key = from.entity.getKeyFromColumns(r, from.startColumn);
                //trace("key is " ~ key.toString);
                row = sess.peekFromCache(from.entity.name, key);
                if (row is null) {
                    //trace("row not found in cache");
                    row = (objectContainer !is null && i == 0) ? objectContainer : from.entity.createEntity();
                    //trace("reading all columns");
                    sess.metaData.readAllColumns(row, r, from.startColumn);
                    sess.putToCache(from.entity.name, key, row);
                } else if (objectContainer !is null) {
                    //trace("copying all properties to existing container");
                    from.entity.copyAllProperties(objectContainer, row);
                }
            }
            relations[i] = row;
        }
        //trace("fill relations...");
        // fill relations
        for (int i = 0; i < query.select.length; i++) {
            if (relations[i] is null)
                continue;
            FromClauseItem from = query.select[i].from;
            auto ei = from.entity;
            for (int j=0; j<ei.length; j++) {
                auto pi = ei[j];
                if (pi.oneToOne || pi.manyToOne) {
                    trace("updating relations for " ~ from.pathString ~ "." ~ pi.propertyName);
                    FromClauseItem rfrom = findRelation(from, pi);
                    if (rfrom !is null && rfrom.selectIndex >= 0) {
                        Object rel = relations[rfrom.selectIndex];
                        pi.setObjectFunc(relations[i], rel);
                    } else {
                        if (pi.columnName !is null) {
                            trace("relation " ~ pi.propertyName ~ " has column name");
                            if (r.isNull(from.startColumn + pi.columnOffset)) {
                                // FK is null, set NULL to field
                                pi.setObjectFunc(relations[i], null);
                                trace("relation " ~ pi.propertyName ~ " has null FK");
                            } else {
                                Variant id = r.getVariant(from.startColumn + pi.columnOffset);
                                Object existing = sess.peekFromCache(pi.referencedEntity.name, id);
                                if (existing !is null) {
                                    trace("existing relation found in cache");
                                    pi.setObjectFunc(relations[i], existing);
                                } else {
                                    // FK is not null
                                    if (pi.lazyLoad) {
                                        // lazy load
                                        trace("scheduling lazy load for " ~ from.pathString ~ "." ~ pi.propertyName ~ " with FK " ~ id.toString);
                                        LazyObjectLoader loader = new LazyObjectLoader(sess.accessor, pi, id);
                                        pi.setObjectDelegateFunc(relations[i], &loader.load);
                                    } else {
                                        // delayed load
                                        trace("relation " ~ pi.propertyName ~ " with FK " ~ id.toString() ~ " will be loaded later");
                                        loadMap.add(pi, id, relations[i]); // to load later
                                    }
                                }
                            }
                        } else {
                            // TODO:
                            assert(false, "relation " ~ pi.propertyName ~ " has no column name. To be implemented.");
                        }
                    }
                } else if (pi.oneToMany || pi.manyToMany) {
                    Variant id = ei.getKey(relations[i]);
                    if (pi.lazyLoad) {
                        // lazy load
                        trace("creating lazy loader for " ~ from.pathString ~ "." ~ pi.propertyName ~ " by FK " ~ id.toString);
                        LazyCollectionLoader loader = new LazyCollectionLoader(sess.accessor, pi, id);
                        pi.setCollectionDelegateFunc(relations[i], &loader.load);
                    } else {
                        // delayed load
                        trace("Relation " ~ from.pathString ~ "." ~ pi.propertyName ~ " will be loaded later by FK " ~ id.toString);
                        loadMap.add(pi, id, relations[i]); // to load later
                    }
                }
            }
        }
        return relations[0];
    }

	/// Return the query results as a List of entity objects
	override Object[] listObjects() {
        return listObjects(null);
	}

    private void delayedLoadRelations(PropertyLoadMap loadMap) {
        loadMap = new PropertyLoadMap(loadMap);

        auto types = loadMap.keys;
        trace("delayedLoadRelations " ~ to!string(loadMap.length));

        foreach(pi; types) {
            trace("delayedLoadRelations " ~ pi.entity.name ~ "." ~ pi.propertyName);
            assert(pi.referencedEntity !is null);
            auto map = loadMap.remove(pi);
            if (map.length == 0)
                continue;
            //trace("delayedLoadRelations " ~ pi.entity.name ~ "." ~ pi.propertyName);
            string keys = map.createCommaSeparatedKeyList();
            if (pi.oneToOne || pi.manyToOne) {
                if (pi.columnName !is null) {
                    Variant[] unknownKeys;
                    Object[] list = sess.lookupCache(pi.referencedEntity.name, map.keys, unknownKeys);
                    if (unknownKeys.length > 0) {
                        string hql = "FROM " ~ pi.referencedEntity.name ~ " WHERE " ~ pi.referencedEntity.keyProperty.propertyName ~ " IN (" ~ createCommaSeparatedKeyList(unknownKeys) ~ ")";
                        trace("delayedLoadRelations: loading " ~ pi.propertyName ~ " HQL: " ~ hql);
                        QueryImpl q = cast(QueryImpl)sess.createQuery(hql);
                        Object[] fromDB = q.listObjects(null, loadMap);
                        list ~= fromDB;
                        trace("delayedLoadRelations: objects loaded " ~ to!string(fromDB.length));
                    } else {
                        trace("all objects found in cache");
                    }
                    trace("delayedLoadRelations: updating");
                    foreach(rel; list) {
                        trace("delayedLoadRelations: reading key from " ~ pi.referencedEntity.name);
                        Variant key = pi.referencedEntity.getKey(rel);
                        //trace("map length before: " ~ to!string(map.length));
                        auto objectsToUpdate = map[key].list;
                        //trace("map length after: " ~ to!string(map.length));
                        //trace("updating relations with key " ~ key.toString() ~ " (" ~ to!string(objectsToUpdate.length) ~ ")");
                        foreach(obj; objectsToUpdate) {
                            pi.setObjectFunc(obj, rel);
                        }
                    }
                } else {
                    assert(false, "Delayed loader for non-join column is not yet implemented for OneToOne and ManyToOne");
                }
            } else if (pi.oneToMany || pi.manyToMany) {
                // The referenced property has a column referring back to this entity.
                string hql = "FROM " ~ pi.referencedEntity.name ~ " WHERE " ~ pi.referencedPropertyName ~ "." ~ pi.entity.keyProperty.propertyName ~ " IN (" ~ keys ~ ")";
                trace("delayedLoadRelations: loading " ~ pi.propertyName ~ " HQL: " ~ hql);
                QueryImpl q = cast(QueryImpl)sess.createQuery(hql);
                assert(q !is null);
                Object[] list = q.listObjects(null, loadMap);
                trace("delayedLoadRelations oneToMany/manyToMany: objects loaded " ~ to!string(list.length));
                EntityCollections collections = new EntityCollections();
                // group by referenced PK
                foreach(rel; list) {
                    trace("delayedLoadRelations oneToMany/manyToMany: reading reference from " ~ pi.referencedEntity.name ~ "." ~ pi.referencedProperty.propertyName ~ " joinColumn=" ~ pi.referencedProperty.columnName);
                    assert(pi.referencedProperty.manyToOne, "property referenced from OneToMany should be ManyToOne");
                    assert(pi.referencedProperty.getObjectFunc !is null);
                    assert(rel !is null);
                    //trace("delayedLoadRelations oneToMany: reading object " ~ rel.classinfo.toString);
                    Object obj = pi.referencedProperty.getObjectFunc(rel);
                    //trace("delayedLoadRelations oneToMany: object is read");
                    if (obj !is null) {
                        //trace("delayedLoadRelations oneToMany: object is not null");
                        //trace("pi.entity.name=" ~ pi.entity.name ~ ", obj is " ~ obj.classinfo.toString);
                        //trace("obj = " ~ obj.toString);
                        //trace("pi.entity.keyProperty=" ~ pi.entity.keyProperty.propertyName);
                        //assert(pi.entity.keyProperty.getFunc !is null);
                        //Variant k = pi.entity.keyProperty.getFunc(obj);
                        //trace("key=" ~ k.toString);
                        Variant key = pi.entity.getKey(obj);
                        collections[key] ~= rel;
                        //collections.add(k, rel);
                    }
                }
                // update objects
                foreach(key; collections.keys) {
                    auto objectsToUpdate = map[key].list;
                    foreach(obj; objectsToUpdate) {
                        pi.setCollectionFunc(obj, collections[key]);
                    }
                }
            }
        }
    }

    /// Return the query results as a List of entity objects
    Object[] listObjects(Object placeFirstObjectHere) {
        PropertyLoadMap loadMap = new PropertyLoadMap();
        return listObjects(placeFirstObjectHere, loadMap);
    }

    /// Return the query results as a List of entity objects
    Object[] listObjects(Object placeFirstObjectHere, PropertyLoadMap loadMap) {
        trace("Entering listObjects " ~ query.hql);
        auto ei = query.entity;
        enforceHelper!SessionException(ei !is null, "No entity expected in result of query " ~ getQueryString());
        params.checkAllParametersSet();
        sess.checkClosed();

        Object[] res;


        trace("SQL: " ~ query.sql);
        PreparedStatement stmt = sess.conn.prepareStatement(query.sql);
        scope(exit) stmt.close();
        params.applyParams(stmt);
        ResultSet rs = stmt.executeQuery();
        assert(query.select !is null && query.select.length > 0);
        int startColumn = query.select[0].from.startColumn;
        {
            scope(exit) rs.close();
            while(rs.next()) {
                //trace("read relations...");
                Object row = readRelations(res.length > 0 ? null : placeFirstObjectHere, rs, loadMap);
                if (row !is null)
                    res ~= row;
            }
        }
        if (loadMap.length > 0) {
            trace("relation properties scheduled for load: loadMap.length == " ~ to!string(loadMap.length));
            delayedLoadRelations(loadMap);
        }
        trace("Exiting listObjects " ~ query.hql);
        return res.length > 0 ? res : null;
    }

    /// Return the query results as a List which each row as Variant array
	override Variant[][] listRows() {
		params.checkAllParametersSet();
		sess.checkClosed();

		Variant[][] res;

		//trace("SQL: " ~ query.sql);
		PreparedStatement stmt = sess.conn.prepareStatement(query.sql);
		scope(exit) stmt.close();
		params.applyParams(stmt);
		ResultSet rs = stmt.executeQuery();
		scope(exit) rs.close();
		while(rs.next()) {
			Variant[] row = new Variant[query.colCount];
			for (int i = 1; i<=query.colCount; i++)
				row[i - 1] = rs.getVariant(i);
			res ~= row;
		}
		return res.length > 0 ? res : null;
	}

	/// Bind a value to a named query parameter.
	override protected Query setParameterVariant(string name, Variant val) {
		params.setParameter(name, val);
		return this;
	}
}

class LazyObjectLoader {
    const PropertyInfo pi;
    Variant id;
    SessionAccessor sess;
    this(SessionAccessor sess, const PropertyInfo pi, Variant id) {
        trace("Created lazy loader for " ~ pi.referencedEntityName ~ " with id " ~ id.toString);
        this.pi = pi;
        this.id = id;
        this.sess = sess;
    }
    Object load() {
        trace("LazyObjectLoader.load()");
        trace("lazy loading of " ~ pi.referencedEntityName ~ " with id " ~ id.toString);
        return sess.get().loadObject(pi.referencedEntityName, id);
    }
}

class LazyCollectionLoader {
    const PropertyInfo pi;
    Variant fk;
    SessionAccessor sess;
    this(SessionAccessor sess, const PropertyInfo pi, Variant fk) {
        assert(!pi.oneToMany || (pi.referencedEntity !is null && pi.referencedProperty !is null), "LazyCollectionLoader: No referenced property specified for OneToMany foreign key column");
        trace("Created lazy loader for collection for references " ~ pi.entity.name ~ "." ~ pi.propertyName ~ " by id " ~ fk.toString);
        this.pi = pi;
        this.fk = fk;
        this.sess = sess;
    }
    Object[] load() {
        trace("LazyObjectLoader.load()");
        trace("lazy loading of references " ~ pi.entity.name ~ "." ~ pi.propertyName ~ " by id " ~ fk.toString);
        Object[] res = sess.get().loadReferencedObjects(pi.entity, pi.propertyName, fk);
        return res;
    }
}

