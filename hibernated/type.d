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
