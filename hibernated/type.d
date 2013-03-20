module hibernated.type;

import std.datetime;

class NullableNumber {
	bool is_null;
}

class NumberBox(T) : NullableNumber {
	T value;
	this(T v) { this.value = v; }
}

alias NumberBox!int Integer;

class Type {
public:
	immutable string getName() { return ""; }
	immutable TypeInfo getReturnedClass() { return null; }
}

class StringType : Type {
public:
	override immutable string getName() { return "String"; }
	override immutable TypeInfo getReturnedClass() { return typeid(string); }

}

class IntegerType : Type {
public:
	override immutable string getName() { return "Integer"; }
	override immutable TypeInfo getReturnedClass() { return typeid(int); }

}

class BigIntegerType : Type {
public:
	override immutable string getName() { return "BigInteger"; }
	override immutable TypeInfo getReturnedClass() { return typeid(int); }
	
}

class DateTimeType : Type {
public:
	override immutable string getName() { return "DateTime"; }
	override immutable TypeInfo getReturnedClass() { return typeid(DateTime); }
}

class DateType : Type {
public:
	override immutable string getName() { return "Date"; }
	override immutable TypeInfo getReturnedClass() { return typeid(Date); }
}

class TimeType : Type {
public:
	override immutable string getName() { return "Time"; }
	override immutable TypeInfo getReturnedClass() { return typeid(TimeOfDay); }
}

class ByteArrayBlobType : Type {
public:
	override immutable string getName() { return "ByteArray"; }
	override immutable TypeInfo getReturnedClass() { return typeid(byte[]); }
}

class UbyteArrayBlobType : Type {
public:
	override immutable string getName() { return "UbyteArray"; }
	override immutable TypeInfo getReturnedClass() { return typeid(ubyte[]); }
}

