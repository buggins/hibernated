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
 * Lazy loader. 
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

//	T setValue(T newValue) {
//        return opAssign(newValue);
//	}
//	
//	void setDelegate(delegate_t lazyLoader) {
//		return opAssign(lazyLoader);
//	}


//    T opCall() {
//        //writeln("Lazy! opCall()");
//        //writeln("Lazy! opCall() delegate " ~ (_delegate !is null ? "is not null" : "is null"));
//        if (_delegate !is null) {
//            //writeln("Lazy! opCall() Delegate is set! Calling it to get value");
//            T value = cast(T)_delegate();
//            //writeln("Lazy! opCall() delegate returned value " ~ value.classinfo.toString);
//            opAssign(value);
//        } else {
//            //writeln("Lazy! opCall() Returning value instantly");
//        }
//        return _value;
//    }
//    
//    T opCall(T newValue) {
//        return opAssign(newValue);
//    }
//    
//    void opCall(delegate_t lazyLoader) {
//        return opAssign(lazyLoader);
//    }


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

    //TODO: is it possible to use implicit cast of Lazy!T to T using opCall()?
    alias get this;
}

version(unittest) {


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
