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
import hibernated.query;

/// Factory to create HibernateD Sessions - similar to org.hibernate.SessionFactory
interface SessionFactory {
	void close();
	bool isClosed();
	Session openSession();
}

/// Session - main interface to load and persist entities -- similar to org.hibernate.Session
abstract class Session
{
    EntityMetaData getMetaData();

	/// not supported in current implementation
	Transaction beginTransaction();
	/// not supported in current implementation
	void cancelQuery();
	/// not supported in current implementation
	void clear();

	/// closes session
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

    /// renamed from Session.delete
    void remove(Object object);

	/// Create a new instance of Query for the given HQL query string
	Query createQuery(string queryString);
}

/// Transaction interface: TODO
interface Transaction {
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
	Query setParameter(string name, Variant val);
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
        enforceEx!CacheException((key in items) !is null, "entity " ~ name ~ " with key " ~ key.toString() ~ " not found in cache");
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
        enforceEx!LazyInitializationException(_session !is null, "Cannot read from closed session");
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
        enforceEx!SessionException(!closed, "Session is closed");
    }

    this(SessionFactoryImpl sessionFactory, EntityMetaData metaData, Dialect dialect, DataSource connectionPool) {
        this.sessionFactory = sessionFactory;
        this.metaData = metaData;
        this.dialect = dialect;
        this.connectionPool = connectionPool;
        this.conn = connectionPool.getConnection();
        this._accessor = new SessionAccessor(this);
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
        _accessor.onSessionClosed();
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
        enforceEx!ObjectNotFoundException(obj !is null, "Entity " ~ entityName ~ " with id " ~ to!string(id) ~ " not found");
        return obj;
    }

    /// Read the persistent state associated with the given identifier into the given transient instance
    override void loadObject(Object obj, Variant id) {
        auto info = metaData.findEntityForObject(obj);
        Object found = getObject(info, obj, id);
        enforceEx!ObjectNotFoundException(found !is null, "Entity " ~ info.name ~ " with id " ~ to!string(id) ~ " not found");
    }

    /// Read the persistent state associated with the given identifier into the given transient instance
    Object getObject(const EntityInfo info, Object obj, Variant id) {
        string hql = "FROM " ~ info.name ~ " WHERE " ~ info.getKeyProperty().propertyName ~ "=:Id";
        Query q = createQuery(hql).setParameter("Id", id);
        Object res = q.uniqueResult(obj);
        return res;
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
        string query = metaData.generateFindByPkForEntity(info);
        enforceEx!TransientObjectException(info.isKeySet(obj), "Cannot refresh entity " ~ info.name ~ ": no Id specified");
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
            enforceEx!ObjectNotFoundException(false, "Entity " ~ info.name ~ " with id " ~ to!string(id) ~ " not found");
        }
    }

    /// Persist the given transient instance, first assigning a generated identifier if not assigned; returns generated value
    override Variant save(Object obj) {
        auto info = metaData.findEntityForObject(obj);
        if (!info.isKeySet(obj)) {
            if (info.getKeyProperty().generated) {
                // autogenerated on DB side
				string query = metaData.generateInsertNoKeyForEntity(info);
				PreparedStatement stmt = conn.prepareStatement(query);
				scope(exit) stmt.close();
				metaData.writeAllColumns(obj, stmt, 1, true);
				Variant generatedKey;
				stmt.executeUpdate(generatedKey);
				info.setKey(obj, generatedKey);
				return info.getKey(obj);
            } else if (info.getKeyProperty().generatorFunc !is null) {
                // has generator function
                Variant generatedKey = info.getKeyProperty().generatorFunc(conn, info.getKeyProperty());
                info.setKey(obj, generatedKey);
                string query = metaData.generateInsertAllFieldsForEntity(info);
                PreparedStatement stmt = conn.prepareStatement(query);
                scope(exit) stmt.close();
                metaData.writeAllColumns(obj, stmt, 1);
                stmt.executeUpdate();
                return info.getKey(obj);
            } else {
                throw new PropertyValueException("Key is not set and no generator is specified");
            }
        } else {
			string query = metaData.generateInsertAllFieldsForEntity(info);
			PreparedStatement stmt = conn.prepareStatement(query);
			scope(exit) stmt.close();
			metaData.writeAllColumns(obj, stmt, 1);
			stmt.executeUpdate();
			return info.getKey(obj);
        }
    }

	/// Persist the given transient instance.
	override void persist(Object obj) {
        auto info = metaData.findEntityForObject(obj);
        enforceEx!TransientObjectException(info.isKeySet(obj), "Cannot persist entity w/o key assigned");
		string query = metaData.generateInsertAllFieldsForEntity(info);;
		PreparedStatement stmt = conn.prepareStatement(query);
		scope(exit) stmt.close();
		metaData.writeAllColumns(obj, stmt, 1);
		stmt.executeUpdate();
	}

    override void update(Object obj) {
        auto info = metaData.findEntityForObject(obj);
        enforceEx!TransientObjectException(info.isKeySet(obj), "Cannot persist entity w/o key assigned");
		string query = metaData.generateUpdateForEntity(info);
		//writeln("Query: " ~ query);
		PreparedStatement stmt = conn.prepareStatement(query);
		scope(exit) stmt.close();
		int columnCount = metaData.writeAllColumns(obj, stmt, 1, true);
		info.keyProperty.writeFunc(obj, stmt, columnCount + 1);
		stmt.executeUpdate();
	}

    // renamed from Session.delete since delete is D keyword
    override void remove(Object obj) {
        auto info = metaData.findEntityForObject(obj);
		string query = "DELETE FROM " ~ info.tableName ~ " WHERE " ~ info.getKeyProperty().columnName ~ "=?";
		PreparedStatement stmt = conn.prepareStatement(query);
		info.getKeyProperty().writeFunc(obj, stmt, 1);
		stmt.executeUpdate();
	}

	/// Create a new instance of Query for the given HQL query string
	override Query createQuery(string queryString) {
		return new QueryImpl(this, queryString);
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
        enforceEx!SessionException(!closed, "Session factory is closed");
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
    if (v.convertsTo!long)
        return Variant(v.get!long);
    else if (v.convertsTo!ulong)
        return Variant(v.get!ulong);
    return Variant(v.toString);
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
        return createCommaSeparatedKeyList(map.keys);
    }
    string createCommaSeparatedKeyList(Variant[] list) {
        assert(map.length > 0);
        string res;
        foreach(v; list) {
            if (res.length > 0)
                res ~= ", ";
            if (v.convertsTo!long || v.convertsTo!ulong) {
                res ~= v.toString();
            } else {
                // TODO: add escaping
                res ~= "'" ~ v.toString() ~ "'";
            }
        }
        return res;
    }
}

/// task to load reference entity
class EntityCollections {
    private ObjectList[Variant] _map; // ID to object list
    @property ref ObjectList[Variant] map() { return _map; }
    @property Variant[] keys() { return _map.keys; }
    @property int length() { return cast(int)_map.length; }
    ref Object[] opIndex(Variant key) {
        //writeln("searching for key " ~ key.toString);
        Variant id = normalize(key);
        if ((id in _map) is null) {
            //writeln("creating new item");
            _map[id] = ObjectList();
        }
        //assert(length > 0);
        //writeln("returning item");
        return _map[id].list;
    }
    void add(ref Variant id, Object obj) {
        auto item = opIndex(id);
        //writeln("item count = " ~ to!string(item.length));
        item ~= obj;
    }
}

class PropertyLoadMap {
    private PropertyLoadItem[const PropertyInfo] _map;
    PropertyLoadItem opIndex(const PropertyInfo prop) {
        if ((prop in _map) is null) {
            //writeln("creating new PropertyLoadItem for " ~ prop.propertyName);
            _map[prop] = new PropertyLoadItem(prop);
        }
        assert(_map.length > 0);
        return _map[prop];
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
        //writeln("QueryImpl(): HQL: " ~ queryString);
        QueryParser parser = new QueryParser(sess.metaData, queryString);
        //writeln("parsing");
		this.query = parser.makeSQL(sess.dialect);
        //writeln("SQL: " ~ this.query.sql);
        params = query.createParams();
        //writeln("exiting QueryImpl()");
    }

	///Get the query string.
	override string getQueryString() {
		return query.hql;
	}

	/// Convenience method to return a single instance that matches the query, or null if the query returns no results.
	override Object uniqueObject() {
        return uniqueResult(null);
	}

    /// Convenience method to return a single instance that matches the query, or null if the query returns no results. Reusing existing buffer.
    override Object uniqueObject(Object obj) {
        Object[] rows = listObjects(obj);
        if (rows == null)
            return null;
        enforceEx!NonUniqueResultException(rows.length == 1, "Query returned more than one object: " ~ getQueryString());
        return rows[0];
    }

	/// Convenience method to return a single instance that matches the query, or null if the query returns no results.
	override Variant[] uniqueRow() {
		Variant[][] rows = listRows();
		if (rows == null)
			return null;
        enforceEx!NonUniqueResultException(rows.length == 1, "Query returned more than one row: " ~ getQueryString());
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
        //writeln("select clause len = " ~ to!string(query.select.length));
        // read all related objects from DB row
        for (int i = 0; i < query.select.length; i++) {
            FromClauseItem from = query.select[i].from;
            //writeln("reading " ~ from.entityName);
            Object row;
            if (!from.entity.isKeyNull(r, from.startColumn)) {
                //writeln("key is not null");
                Variant key = from.entity.getKey(r, from.startColumn);
                //writeln("key is " ~ key.toString);
                row = sess.peekFromCache(from.entity.name, key);
                if (row is null) {
                    //writeln("row not found in cache");
                    row = (objectContainer !is null && i == 0) ? objectContainer : from.entity.createEntity();
                    //writeln("reading all columns");
                    sess.metaData.readAllColumns(row, r, from.startColumn);
                    sess.putToCache(from.entity.name, key, row);
                } else if (objectContainer !is null) {
                    //writeln("copying all properties to existing container");
                    from.entity.copyAllProperties(objectContainer, row);
                }
            }
            relations[i] = row;
        }
        //writeln("fill relations...");
        // fill relations
        for (int i = 0; i < query.select.length; i++) {
            if (relations[i] is null)
                continue;
            FromClauseItem from = query.select[i].from;
            auto ei = from.entity;
            for (int j=0; j<ei.length; j++) {
                auto pi = ei[j];
                if (pi.oneToOne || pi.manyToOne) {
                    writeln("updating relations for " ~ from.pathString ~ "." ~ pi.propertyName);
                    FromClauseItem rfrom = findRelation(from, pi);
                    if (rfrom !is null && rfrom.selectIndex >= 0) {
                        Object rel = relations[rfrom.selectIndex];
                        pi.setObjectFunc(relations[i], rel);
                    } else {
                        if (pi.columnName !is null) {
                            writeln("relation " ~ pi.propertyName ~ " has column name");
                            if (r.isNull(from.startColumn + pi.columnOffset)) {
                                // FK is null, set NULL to field
                                pi.setObjectFunc(relations[i], null);
                                writeln("relation " ~ pi.propertyName ~ " has null FK");
                            } else {
                                Variant id = r.getVariant(from.startColumn + pi.columnOffset);
                                Object existing = sess.peekFromCache(pi.referencedEntity.name, id);
                                if (existing !is null) {
                                    writeln("existing relation found in cache");
                                    pi.setObjectFunc(relations[i], existing);
                                } else {
                                    // FK is not null
                                    if (pi.lazyLoad) {
                                        // lazy load
                                        writeln("scheduling lazy load for " ~ from.pathString ~ "." ~ pi.propertyName ~ " with FK " ~ id.toString);
                                        LazyObjectLoader loader = new LazyObjectLoader(sess.accessor, pi, id);
                                        pi.setObjectDelegateFunc(relations[i], &loader.load);
                                    } else {
                                        // delayed load
                                        writeln("relation " ~ pi.propertyName ~ " with FK " ~ id.toString() ~ " will be loaded later");
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
                        writeln("creating lazy loader for " ~ from.pathString ~ "." ~ pi.propertyName ~ " by FK " ~ id.toString);
                        LazyCollectionLoader loader = new LazyCollectionLoader(sess.accessor, pi, id);
                        pi.setCollectionDelegateFunc(relations[i], &loader.load);
                    } else {
                        // delayed load
                        writeln("Relation " ~ from.pathString ~ "." ~ pi.propertyName ~ " will be loaded later by FK " ~ id.toString);
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
        auto types = loadMap.keys;
        writeln("delayedLoadRelations " ~ to!string(loadMap.length));
        foreach(pi; types) {
            writeln("delayedLoadRelations " ~ pi.entity.name ~ "." ~ pi.propertyName);
            assert(pi.referencedEntity !is null);
            auto map = loadMap.remove(pi);
            if (map.length == 0)
                continue;
            //writeln("delayedLoadRelations " ~ pi.entity.name ~ "." ~ pi.propertyName);
            string keys = map.createCommaSeparatedKeyList();
            if (pi.oneToOne || pi.manyToOne) {
                if (pi.columnName !is null) {
                    Variant[] unknownKeys;
                    Object[] list = sess.lookupCache(pi.referencedEntity.name, map.keys, unknownKeys);
                    if (unknownKeys.length > 0) {
                        string hql = "FROM " ~ pi.referencedEntity.name ~ " WHERE " ~ pi.referencedEntity.keyProperty.propertyName ~ " IN (" ~ map.createCommaSeparatedKeyList(unknownKeys) ~ ")";
                        writeln("delayedLoadRelations: loading " ~ pi.propertyName ~ " HQL: " ~ hql);
                        QueryImpl q = cast(QueryImpl)sess.createQuery(hql);
                        Object[] fromDB = q.listObjects(null, loadMap);
                        list ~= fromDB;
                        writeln("delayedLoadRelations: objects loaded " ~ to!string(fromDB.length));
                    } else {
                        writeln("all objects found in cache");
                    }
                    writeln("delayedLoadRelations: updating");
                    foreach(rel; list) {
                        writeln("delayedLoadRelations: reading key from " ~ pi.referencedEntity.name);
                        Variant key = pi.referencedEntity.getKey(rel);
                        //writeln("map length before: " ~ to!string(map.length));
                        auto objectsToUpdate = map[key].list;
                        //writeln("map length after: " ~ to!string(map.length));
                        //writeln("updating relations with key " ~ key.toString() ~ " (" ~ to!string(objectsToUpdate.length) ~ ")");
                        foreach(obj; objectsToUpdate) {
                            pi.setObjectFunc(obj, rel);
                        }
                    }
                } else {
                    assert(false, "Delayed loader for non-join column is not yet implemented for OneToOne and ManyToOne");
                }
            } else if (pi.oneToMany || pi.manyToMany) {
                string hql = "FROM " ~ pi.referencedEntity.name ~ " WHERE " ~ pi.referencedPropertyName ~ "." ~ pi.referencedEntity.keyProperty.propertyName ~ " IN (" ~ keys ~ ")";
                writeln("delayedLoadRelations: loading " ~ pi.propertyName ~ " HQL: " ~ hql);
                QueryImpl q = cast(QueryImpl)sess.createQuery(hql);
                assert(q !is null);
                Object[] list = q.listObjects(null, loadMap);
                writeln("delayedLoadRelations oneToMany/manyToMany: objects loaded " ~ to!string(list.length));
                EntityCollections collections = new EntityCollections();
                // group by referenced PK
                foreach(rel; list) {
                    writeln("delayedLoadRelations oneToMany/manyToMany: reading reference from " ~ pi.referencedEntity.name ~ "." ~ pi.referencedProperty.propertyName ~ " joinColumn=" ~ pi.referencedProperty.columnName);
                    assert(pi.referencedProperty.manyToOne, "property referenced from OneToMany should be ManyToOne");
                    assert(pi.referencedProperty.getObjectFunc !is null);
                    assert(rel !is null);
                    //writeln("delayedLoadRelations oneToMany: reading object " ~ rel.classinfo.toString);
                    Object obj = pi.referencedProperty.getObjectFunc(rel);
                    //writeln("delayedLoadRelations oneToMany: object is read");
                    if (obj !is null) {
                        //writeln("delayedLoadRelations oneToMany: object is not null");
                        //writeln("pi.entity.name=" ~ pi.entity.name ~ ", obj is " ~ obj.classinfo.toString);
                        //writeln("obj = " ~ obj.toString);
                        //writeln("pi.entity.keyProperty=" ~ pi.entity.keyProperty.propertyName);
                        //assert(pi.entity.keyProperty.getFunc !is null);
                        //Variant k = pi.entity.keyProperty.getFunc(obj);
                        //writeln("key=" ~ k.toString);
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
        writeln("Entering listObjects " ~ query.hql);
        auto ei = query.entity;
        enforceEx!SessionException(ei !is null, "No entity expected in result of query " ~ getQueryString());
        params.checkAllParametersSet();
        sess.checkClosed();
        
        Object[] res;


        //writeln("SQL: " ~ query.sql);
        PreparedStatement stmt = sess.conn.prepareStatement(query.sql);
        scope(exit) stmt.close();
        params.applyParams(stmt);
        ResultSet rs = stmt.executeQuery();
        assert(query.select !is null && query.select.length > 0);
        int startColumn = query.select[0].from.startColumn;
        {
            scope(exit) rs.close();
            while(rs.next()) {
                //writeln("read relations...");
                Object row = readRelations(res.length > 0 ? null : placeFirstObjectHere, rs, loadMap);
                if (row !is null)
                    res ~= row;
            }
        }
        if (loadMap.length > 0) {
            writeln("relation properties scheduled for load: loadMap.length == " ~ to!string(loadMap.length));
            delayedLoadRelations(loadMap);
        }
        writeln("Exiting listObjects " ~ query.hql);
        return res.length > 0 ? res : null;
    }
    
    /// Return the query results as a List which each row as Variant array
	override Variant[][] listRows() {
		params.checkAllParametersSet();
		sess.checkClosed();
		
		Variant[][] res;
		
		//writeln("SQL: " ~ query.sql);
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
	override Query setParameter(string name, Variant val) {
		params.setParameter(name, val);
		return this;
	}
}

class LazyObjectLoader {
    const PropertyInfo pi;
    Variant id;
    SessionAccessor sess;
    this(SessionAccessor sess, const PropertyInfo pi, Variant id) {
        writeln("Created lazy loader for " ~ pi.referencedEntityName ~ " with id " ~ id.toString);
        this.pi = pi;
        this.id = id;
        this.sess = sess;
    }
    Object load() {
        writeln("LazyObjectLoader.load()");
        writeln("lazy loading of " ~ pi.referencedEntityName ~ " with id " ~ id.toString);
        // TODO: handle closed session
        return sess.get().loadObject(pi.referencedEntityName, id);
    }
}

class LazyCollectionLoader {
    const PropertyInfo pi;
    Variant fk;
    SessionAccessor sess;
    this(SessionAccessor sess, const PropertyInfo pi, Variant fk) {
        assert(!pi.oneToMany || (pi.referencedEntity !is null && pi.referencedProperty !is null), "LazyCollectionLoader: No referenced property specified for OneToMany foreign key column");
        writeln("Created lazy loader for collection for references " ~ pi.entity.name ~ "." ~ pi.propertyName ~ " by id " ~ fk.toString);
        this.pi = pi;
        this.fk = fk;
        this.sess = sess;
    }
    Object[] load() {
        writeln("LazyObjectLoader.load()");
        writeln("lazy loading of references " ~ pi.entity.name ~ "." ~ pi.propertyName ~ " by id " ~ fk.toString);
        Object[] res = sess.get().loadReferencedObjects(pi.entity, pi.propertyName, fk);
        return res;
    }
}

