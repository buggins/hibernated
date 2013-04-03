/**
 * HibernateD - Object-Relation Mapping for D programming language, with interface similar to Hibernate. 
 * 
 * Hibernate documentation can be found here:
 * $(LINK http://hibernate.org/docs)$(BR)
 * 
 * Source file hibernated/type.d.
 *
 * This module contains declarations of property type description classes.
 * 
 * Copyright: Copyright 2013
 * License:   $(LINK www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Author:   Vadim Lopatin
 */
module hibernated.type;

import std.datetime;
import std.stdio;
import std.traits;

import ddbc.core;

/// base class for all HibernateD exceptions
class HibernatedException : Exception {
    this(string msg, string f = __FILE__, size_t l = __LINE__) { super(msg, f, l); }
    this(Exception causedBy, string f = __FILE__, size_t l = __LINE__) { super(causedBy.msg, f, l); }
}

/// Thrown when the user passes a transient instance to a Session method that expects a persistent instance. 
class TransientObjectException : HibernatedException {
    this(string msg, string f = __FILE__, size_t l = __LINE__) { super(msg, f, l); }
    this(Exception causedBy, string f = __FILE__, size_t l = __LINE__) { super(causedBy.msg, f, l); }
}

/// Something went wrong in the cache
class CacheException : HibernatedException {
    this(string msg, string f = __FILE__, size_t l = __LINE__) { super(msg, f, l); }
    this(Exception causedBy, string f = __FILE__, size_t l = __LINE__) { super(causedBy.msg, f, l); }
}

/// Thrown when the (illegal) value of a property can not be persisted. There are two main causes: a property declared not-null="true" is null or an association references an unsaved transient instance 
class PropertyValueException : HibernatedException {
    this(string msg, string f = __FILE__, size_t l = __LINE__) { super(msg, f, l); }
    this(Exception causedBy, string f = __FILE__, size_t l = __LINE__) { super(causedBy.msg, f, l); }
}

/// A problem occurred translating a Hibernate query to SQL due to invalid query syntax, etc. 
class QueryException : HibernatedException {
    this(string msg, string f = __FILE__, size_t l = __LINE__) { super(msg, f, l); }
    this(Exception causedBy, string f = __FILE__, size_t l = __LINE__) { super(causedBy.msg, f, l); }
}

/// Exception thrown when there is a syntax error in the HQL. 
class QuerySyntaxException : QueryException {
    this(string msg, string f = __FILE__, size_t l = __LINE__) { super(msg, f, l); }
    this(Exception causedBy, string f = __FILE__, size_t l = __LINE__) { super(causedBy.msg, f, l); }
}

/// Parameter invalid or not found in the query
class QueryParameterException : QueryException {
    this(string msg, string f = __FILE__, size_t l = __LINE__) { super(msg, f, l); }
    this(Exception causedBy, string f = __FILE__, size_t l = __LINE__) { super(causedBy.msg, f, l); }
}

/// Indicates that a transaction could not be begun, committed or rolled back. 
class TransactionException : HibernatedException {
    this(string msg, string f = __FILE__, size_t l = __LINE__) { super(msg, f, l); }
    this(Exception causedBy, string f = __FILE__, size_t l = __LINE__) { super(causedBy.msg, f, l); }
}

/// Indicates access to unfetched data outside of a session context. For example, when an uninitialized proxy or collection is accessed after the session was closed. 
class LazyInitializationException : HibernatedException {
    this(string msg, string f = __FILE__, size_t l = __LINE__) { super(msg, f, l); }
    this(Exception causedBy, string f = __FILE__, size_t l = __LINE__) { super(causedBy.msg, f, l); }
}

/// An exception that usually occurs as a result of something screwy in the O-R mappings. 
class MappingException : HibernatedException {
    this(string msg, string f = __FILE__, size_t l = __LINE__) { super(msg, f, l); }
    this(Exception causedBy, string f = __FILE__, size_t l = __LINE__) { super(causedBy.msg, f, l); }
}

/// Thrown when Hibernate could not resolve an object by id, especially when loading an association.
class UnresolvableObjectException : HibernatedException {
    this(string msg, string f = __FILE__, size_t l = __LINE__) { super(msg, f, l); }
    this(Exception causedBy, string f = __FILE__, size_t l = __LINE__) { super(causedBy.msg, f, l); }
}

/// An exception occurs when query result is expected but object is not found in DB.
class ObjectNotFoundException : UnresolvableObjectException {
    this(string msg, string f = __FILE__, size_t l = __LINE__) { super(msg, f, l); }
    this(Exception causedBy, string f = __FILE__, size_t l = __LINE__) { super(causedBy.msg, f, l); }
}

/// Thrown when the user tries to do something illegal with a deleted object. 
class ObjectDeletedException : UnresolvableObjectException {
    this(string msg, string f = __FILE__, size_t l = __LINE__) { super(msg, f, l); }
    this(Exception causedBy, string f = __FILE__, size_t l = __LINE__) { super(causedBy.msg, f, l); }
}

/// Thrown when the user calls a method of a Session that is in an inappropropriate state for the given call (for example, the the session is closed or disconnected). 
class SessionException : HibernatedException {
    this(string msg, string f = __FILE__, size_t l = __LINE__) { super(msg, f, l); }
    this(Exception causedBy, string f = __FILE__, size_t l = __LINE__) { super(causedBy.msg, f, l); }
}

/// Thrown when the application calls Query.uniqueResult() and the query returned more than one result. Unlike all other Hibernate exceptions, this one is recoverable! 
class NonUniqueResultException : HibernatedException {
    this(string msg, string f = __FILE__, size_t l = __LINE__) { super(msg, f, l); }
    this(Exception causedBy, string f = __FILE__, size_t l = __LINE__) { super(causedBy.msg, f, l); }
}


/// Base class for HibernateD property types
class Type {
public:
	immutable SqlType getSqlType() { return SqlType.OTHER; }
	immutable string getName() { return ""; }
	//immutable TypeInfo getReturnedClass() { return null; }
}

class StringType : Type {
private:
	int _length;
public:
	this(int len = 0) { _length = len; }
	@property int length() { return _length; }
	override immutable SqlType getSqlType() { return SqlType.VARCHAR; }
	override immutable string getName() { return "String"; }
	//override immutable TypeInfo getReturnedClass() { return typeid(string); }

}

class NumberType : Type {
protected:
	int _length;
	bool _unsigned;
	SqlType _type;
public:
	this(int len, bool unsigned, SqlType type) {
		_length = len;
		_unsigned = unsigned;
		_type = type;
	}
	@property int length() { return _length; }
	@property bool unsigned() { return _unsigned; }
	override immutable SqlType getSqlType() { return _type; }
	override immutable string getName() { return "Integer"; }
}

class DateTimeType : Type {
public:
	override immutable string getName() { return "DateTime"; }
	//override immutable TypeInfo getReturnedClass() { return typeid(DateTime); }
	override immutable SqlType getSqlType() { return SqlType.DATETIME; }
}

class DateType : Type {
public:
	override immutable string getName() { return "Date"; }
	//override immutable TypeInfo getReturnedClass() { return typeid(Date); }
	override immutable SqlType getSqlType() { return SqlType.DATE; }
}

class TimeType : Type {
public:
	override immutable string getName() { return "Time"; }
	//override immutable TypeInfo getReturnedClass() { return typeid(TimeOfDay); }
	override immutable SqlType getSqlType() { return SqlType.TIME; }
}

class ByteArrayBlobType : Type {
public:
	override immutable string getName() { return "ByteArray"; }
	//override immutable TypeInfo getReturnedClass() { return typeid(byte[]); }
	override immutable SqlType getSqlType() { return SqlType.BLOB; }
}

class UbyteArrayBlobType : Type {
public:
	override immutable string getName() { return "UbyteArray"; }
	//override immutable TypeInfo getReturnedClass() { return typeid(ubyte[]); }
	override immutable SqlType getSqlType() { return SqlType.BLOB; }
}

// TODO
class EntityType : Type {
	private string name;
	private immutable TypeInfo_Class classType;
public:
	this(immutable TypeInfo_Class classType, string className) {
		this.classType = classType;
		this.name = className;
	}
	override immutable string getName() { return name; }
	//override immutable TypeInfo getReturnedClass() { return null; }
}

/**
 * Lazy entity loader. 
 * 
 * 
 */
struct Lazy(T) {
    alias Object delegate() delegate_t;
	private T _value;
	private delegate_t _delegate;

    T opCall() {
        return get();
    }

    @property bool loaded() {
        return _delegate is null;
    }

	T get() {
        //writeln("Lazy! opCall()");
        //writeln("Lazy! opCall() delegate " ~ (_delegate !is null ? "is not null" : "is null"));
        if (_delegate !is null) {
            //writeln("Lazy! opCall() Delegate is set! Calling it to get value");
            T value = cast(T)_delegate();
            //writeln("Lazy! opCall() delegate returned value " ~ value.classinfo.toString);
            opAssign(value);
        } else {
            //writeln("Lazy! opCall() Returning value instantly");
        }
		return _value;
	}

	T opCast(TT)() if (is(TT == T)) {
		return get();
	}

	T opAssign(T v) {
        //writeln("Lazy! opAssign(value)");
        _value = v;
		_delegate = null;
		return _value;
	}

    ref Lazy!T opAssign(ref Lazy!T v) {
        //writeln("Lazy! opAssign(value)");
        _value = v._value;
        _delegate = v._delegate;
        return this;
    }
    
    void opAssign(delegate_t lazyLoader) {
        //writeln("Lazy! opAssign(delegate)");
        _delegate = lazyLoader;
		_value = null;
	}

    alias get this;
}

/**
 * Lazy entity collection loader. 
 */
struct LazyCollection(T) {
    alias Object[] delegate() delegate_t;
    private T[] _value;
    private delegate_t _delegate;
    
    T[] opCall() {
        return get();
    }
    
    @property bool loaded() {
        return _delegate is null;
    }
    
    ref T[] get() {
        //writeln("Lazy! opCall()");
        //writeln("Lazy! opCall() delegate " ~ (_delegate !is null ? "is not null" : "is null"));
        if (_delegate !is null) {
            //writeln("Lazy! opCall() Delegate is set! Calling it to get value");
            T[] value = cast(T[])_delegate();
            //writeln("Lazy! opCall() delegate returned value " ~ value.classinfo.toString);
            opAssign(value);
        } else {
            //writeln("Lazy! opCall() Returning value instantly");
        }
        return _value;
    }
    
    TT opCast(TT)() if (isArray!TT && isImplicitlyConvertible!(typeof(TT.init[0]), Object)) {
        return cast(TT)get();
    }
    
    T[] opAssign(T[] v) {
        //writeln("Lazy! opAssign(value)");
        _value = v;
        _delegate = null;
        return _value;
    }
    
    ref LazyCollection!T opAssign(ref LazyCollection!T v) {
        //writeln("Lazy! opAssign(value)");
        _value = v._value;
        _delegate = v._delegate;
        return this;
    }
    
    void opAssign(delegate_t lazyLoader) {
        //writeln("Lazy! opAssign(delegate)");
        _delegate = lazyLoader;
        _value = null;
    }
    
    alias get this;
}

unittest {

    class Foo {
        string name;
        this(string v) {
            name = v;
        }
    }
    struct LazyVar(T) {
        T a;
        int b;
        T opCall() {
            b++;
            return a;
        }
        alias opCall this;
    }
    class TestLazy {
        LazyVar!Foo l;
    }

    auto loader = delegate() {
		return new Foo("lazy loaded");
	};

	Foo res;
	Lazy!Foo field;
	res = field();
	assert(res is null);
	field = loader;
	res = field();
	assert(res.name == "lazy loaded");
	field = new Foo("another string");
	res = cast(Foo)field;
	assert(res.name == "another string");

	static class Bar {
		@property Lazy!Foo field;
	}
	Bar bar = new Bar();
	bar.field = new Foo("name1");
	res = bar.field();

    LazyVar!string s;
    s.a = "10";
    assert(s() == "10");
    assert(s.b == 1);
    s.a = "15";
    assert(s == "15");
    assert(s.b == 2);

    import hibernated.metadata;
    TestLazy tl = new TestLazy();
}

