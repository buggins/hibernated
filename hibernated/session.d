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
        enforceEx!HibernatedException((key in items) !is null, "entity " ~ name ~ " with key " ~ key.toString() ~ " not found in cache");
        return items[key];
    }
    void put(Variant key, Object obj) {
        items[key] = obj;
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
        return getCache(entityName).hasKey(key);
    }
    
    package Object peekFromCache(string entityName, Variant key) {
        return getCache(entityName).peek(key);
    }

    package Object getFromCache(string entityName, Variant key) {
        return getCache(entityName).get(key);
    }

    package void putToCache(string entityName, Variant key, Object value) {
        return getCache(entityName).put(key, value);
    }
    
    override EntityMetaData getMetaData() {
        return metaData;
    }

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
        enforceEx!HibernatedException(obj !is null, "Entity " ~ entityName ~ " with id " ~ to!string(id) ~ " not found");
        return obj;
    }

    /// Read the persistent state associated with the given identifier into the given transient instance
    override void loadObject(Object obj, Variant id) {
        auto info = metaData.findEntityForObject(obj);
        Object found = getObject(info, obj, id);
        enforceEx!HibernatedException(found !is null, "Entity " ~ info.name ~ " with id " ~ to!string(id) ~ " not found");
    }

    /// Read the persistent state associated with the given identifier into the given transient instance
    Object getObject(const EntityInfo info, Object obj, Variant id) {
        string hql = "FROM " ~ info.name ~ " WHERE " ~ info.getKeyProperty().propertyName ~ "=:Id";
        Query q = createQuery(hql).setParameter("Id", id);
        Object res = q.uniqueResult(obj);
        return res;

//        string query = metaData.generateFindByPkForEntity(info);
//        //writeln("Finder query: " ~ query);
//        PreparedStatement stmt = conn.prepareStatement(query);
//        scope(exit) stmt.close();
//        stmt.setVariant(1, id);
//        ResultSet rs = stmt.executeQuery();
//        //writeln("returned rows: " ~ to!string(rs.getFetchSize()));
//        scope(exit) rs.close();
//        if (rs.next()) {
//            if (obj is null)
//                obj = info.createEntity();
//            //writeln("reading columns");
//            metaData.readAllColumns(obj, rs, 1);
//            //writeln("value: " ~ obj.toString);
//            return obj;
//        } else {
//            // not found!
//            return null;
//        }
    }
    
    /// Re-read the state of the given instance from the underlying database.
    override void refresh(Object obj) {
        auto info = metaData.findEntityForObject(obj);
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

    /// Persist the given transient instance, first assigning a generated identifier if not assigned; returns generated value
    override Variant save(Object obj) {
        auto info = metaData.findEntityForObject(obj);
        if (!info.isKeySet(obj)) {
            if (info.getKeyProperty().generated) {
				string query = metaData.generateInsertNoKeyForEntity(info);
				PreparedStatement stmt = conn.prepareStatement(query);
				scope(exit) stmt.close();
				metaData.writeAllColumns(obj, stmt, 1, true);
				Variant generatedKey;
				stmt.executeUpdate(generatedKey);
				info.setKey(obj, generatedKey);
				return info.getKey(obj);
            } else {
                throw new HibernatedException("Key is not set and no generator is specified");
            }
        } else {
			string query = metaData.generateInsertAllFieldsForEntity(info);;
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
		enforceEx!HibernatedException(info.isKeySet(obj), "Cannot persist entity w/o key assigned");
		string query = metaData.generateInsertAllFieldsForEntity(info);;
		PreparedStatement stmt = conn.prepareStatement(query);
		scope(exit) stmt.close();
		metaData.writeAllColumns(obj, stmt, 1);
		stmt.executeUpdate();
	}

    override void update(Object obj) {
        auto info = metaData.findEntityForObject(obj);
		enforceEx!HibernatedException(info.isKeySet(obj), "Cannot persist entity w/o key assigned");
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
    Variant normalize(Variant v) {
        // variants of different type are not equal, normalize to make sure that keys Variant(1) and Variant(1L) are the same
        if (v.convertsTo!long)
            return Variant(v.get!long);
        else if (v.convertsTo!ulong)
            return Variant(v.get!ulong);
        return Variant(v.toString);
    }
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
        string res;
        foreach(v; map.keys) {
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
		QueryParser parser = new QueryParser(sess.metaData, queryString);
		this.query = parser.makeSQL(sess.dialect);
		params = query.createParams();
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
        enforceEx!HibernatedException(rows.length == 1, "Query returned more than one object: " ~ getQueryString());
        return rows[0];
    }

	/// Convenience method to return a single instance that matches the query, or null if the query returns no results.
	override Variant[] uniqueRow() {
		Variant[][] rows = listRows();
		if (rows == null)
			return null;
		enforceEx!HibernatedException(rows.length == 1, "Query returned more than one row: " ~ getQueryString());
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
        writeln("fill relations...");
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
                    if (pi.lazyLoad) {
                        // TODO: support lazy loader
                    } else {
                        FromClauseItem rfrom = findRelation(from, pi);
                        if (rfrom !is null && rfrom.selectIndex >= 0) {
                            Object rel = relations[rfrom.selectIndex];
                            pi.setObjectFunc(relations[i], rel);
                        } else {
                            writeln("not found loaded oneToOne relation for " ~ from.pathString ~ "." ~ pi.propertyName);
                            if (pi.columnName !is null) {
                                writeln("relation " ~ pi.propertyName ~ " has column name");
                                if (r.isNull(from.startColumn + pi.columnOffset)) {
                                    // FK is null, set NULL to field
                                    pi.setObjectFunc(relations[i], null);
                                    writeln("relation " ~ pi.propertyName ~ " has null FK");
                                } else {
                                    // FK is not null
                                    Variant id = r.getVariant(from.startColumn + pi.columnOffset);
                                    writeln("relation " ~ pi.propertyName ~ " with FK " ~ id.toString() ~ " will be loaded later");
                                    loadMap.add(pi, id, relations[i]); // to load later
                                }
                            } else {
                                writeln("relation " ~ pi.propertyName ~ " has no column name");
                            }
                        }
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
        foreach(pi; types) {
            assert(pi.referencedEntity !is null);
            auto map = loadMap.remove(pi);
            if (map.length == 0)
                continue;
            string keys = map.createCommaSeparatedKeyList();
            string hql = "FROM " ~ pi.referencedEntity.name ~ " WHERE " ~ pi.referencedEntity.keyProperty.propertyName ~ " IN (" ~ keys ~ ")";
            writeln("delayedLoadRelations: loading " ~ pi.propertyName ~ " HQL: " ~ hql);
            QueryImpl q = cast(QueryImpl)sess.createQuery(hql);

            Object[] list = q.listObjects(null, loadMap);
            writeln("delayedLoadRelations: objects loaded " ~ to!string(list.length));
            foreach(rel; list) {
                Variant key = pi.referencedEntity.getKey(rel);
                //writeln("map length before: " ~ to!string(map.length));
                auto objectsToUpdate = map[key].list;
                //writeln("map length after: " ~ to!string(map.length));
                //writeln("updating relations with key " ~ key.toString() ~ " (" ~ to!string(objectsToUpdate.length) ~ ")");
                foreach(obj; objectsToUpdate) {
                    pi.setObjectFunc(obj, rel);
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
        writeln("Entering loadObjects");
        auto ei = query.entity;
        enforceEx!HibernatedException(ei !is null, "No entity expected in result of query " ~ getQueryString());
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
                writeln("read relations...");
                Object row = readRelations(res.length > 0 ? null : placeFirstObjectHere, rs, loadMap);
                if (row !is null)
                    res ~= row;
            }
        }
        if (loadMap.length > 0) {
            writeln("relation properties scheduled for load: loadMap.length == " ~ to!string(loadMap.length));
            delayedLoadRelations(loadMap);
        }
        writeln("Exiting loadObjects");
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


