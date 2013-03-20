module hibernated.metadata;

import std.conv;
import std.exception;
import std.stdio;
import std.string;
import std.traits;
import std.typecons;
import std.typetuple;
import std.variant;

import ddbc.core;
import ddbc.common;

import hibernated.annotations;
import hibernated.core;
import hibernated.type;
import hibernated.session;
import hibernated.dialect;
import hibernated.dialects.mysqldialect;

//interface ClassMetadata {
//	immutable string getEntityName();
//	immutable TypeInfo getMappedClass();
//	immutable string[] getPropertyNames();
//}



/// Metadata of entity property
class PropertyInfo {
public:
	alias void function(Object, DataSetReader, int index) ReaderFunc;
	alias void function(Object, DataSetWriter, int index) WriterFunc;
	alias Variant function(Object) GetVariantFunc;
	alias void function(Object, Variant value) SetVariantFunc;
	alias bool function(Object) KeyIsSetFunc;
	alias bool function(Object) IsNullFunc;
	string propertyName;
	string columnName;
	Type columnType;
	int length;
	bool key;
	bool generated;
	bool nullable;
	ReaderFunc readFunc;
	WriterFunc writeFunc;
	GetVariantFunc getFunc;
	SetVariantFunc setFunc;
	KeyIsSetFunc keyIsSetFunc;
	IsNullFunc isNullFunc;
	this(string propertyName, string columnName, Type columnType, int length, bool key, bool generated, bool nullable, ReaderFunc reader, WriterFunc writer, GetVariantFunc getFunc, SetVariantFunc setFunc, KeyIsSetFunc keyIsSetFunc, IsNullFunc isNullFunc) {
		this.propertyName = propertyName;
		this.columnName = columnName;
		this.columnType = columnType;
		this.length = length;
		this.key = key;
		this.generated = generated;
		this.nullable = nullable;
		this.readFunc = reader;
		this.writeFunc = writer;
		this.getFunc = getFunc;
		this.setFunc = setFunc;
		this.keyIsSetFunc = keyIsSetFunc;
		this.isNullFunc = isNullFunc;
	}
}

/// Metadata of single entity
class EntityInfo {
	string name;
	string tableName;
	PropertyInfo [] properties;
	PropertyInfo [string] propertyMap;
	TypeInfo_Class classInfo;
    int keyIndex;
    PropertyInfo keyProperty;
	public this(string name, string tableName, PropertyInfo [] properties, TypeInfo_Class classInfo) {
		this.name = name;
		this.tableName = tableName;
		this.properties = properties;
		this.classInfo = classInfo;
		PropertyInfo[string] map;
		foreach(i, p; properties) {
			map[p.propertyName] = p;
            if (p.key) {
                keyIndex = cast(int)i;
                keyProperty = p;
            }
        }
		this.propertyMap = map;
        enforceEx!HibernatedException(keyProperty !is null, "No key specified for entity " ~ name);
	}
	/// returns key value as Variant
	Variant getKey(Object obj) { return keyProperty.getFunc(obj); }
	/// sets key value from Variant
	void setKey(Object obj, Variant value) { keyProperty.setFunc(obj, value); }
    /// returns property info for key property
    PropertyInfo getKeyProperty() { return keyProperty; }
    /// checks if primary key is set (for non-nullable member types like int or long, 0 is considered as non-set)
	bool isKeySet(Object obj) { return keyProperty.keyIsSetFunc(obj); }
	/// checks if property value is null
	bool isNull(Object obj) { return keyProperty.isNullFunc(obj); }
	/// returns property value as Variant
	Variant getPropertyValue(Object obj, string propertyName) { return findProperty(propertyName).getFunc(obj); }
	/// sets property value from Variant
	void setPropertyValue(Object obj, string propertyName, Variant value) { return findProperty(propertyName).setFunc(obj, value); }
	/// returns all properties as array
	PropertyInfo[] getProperties() { return properties; }
	/// returns map of property name to property metadata
	PropertyInfo[string] getPropertyMap() { return propertyMap; }
	/// returns number of properties
	ulong getPropertyCount() { return properties.length; }
	/// returns number of properties
	ulong getPropertyCountExceptKey() { return properties.length - 1; }
	/// returns property by index
	PropertyInfo getProperty(int propertyIndex) { return properties[propertyIndex]; }
	/// returns property by name, throws exception if not found
	PropertyInfo findProperty(string propertyName) { try { return propertyMap[propertyName]; } catch (Throwable e) { throw new HibernatedException("No property " ~ propertyName ~ " found in entity " ~ name); } }
	/// create instance of entity object (using default constructor)
	Object createEntity() { return Object.factory(classInfo.name); }
}

bool isHibernatedAnnotation(alias t)() {
	return is(typeof(t) == Id) || is(typeof(t) == Entity) || is(typeof(t) == Column) || is(typeof(t) == Table) || is(typeof(t) == Generated) || is(typeof(t) == Id) || t.stringof == Column.stringof || t.stringof == Id.stringof || t.stringof == Generated.stringof || t.stringof == Entity.stringof;
}

bool isHibernatedEntityAnnotation(alias t)() {
	return is(typeof(t) == Entity) || t.stringof == Entity.stringof;
}

string capitalizeFieldName(immutable string name) {
	return toUpper(name[0..1]) ~ name[1..$];
}

string getterNameToFieldName(immutable string name) {
	if (name[0..3] == "get")
		return toLower(name[3..4]) ~ name[4..$];
	if (name[0..2] == "is")
		return toLower(name[2..3]) ~ name[3..$];
	return "_" ~ name;
}

string getterNameToSetterName(immutable string name) {
	if (name[0..3] == "get")
		return "set" ~ name[3..$]; // e.g. getValue() -> setValue()
	if (name[0..2] == "is")
		return "set" ~ toUpper(name[0..1]) ~ name[1..$]; // e.g.  isDefault()->setIsDefault()
	return "_" ~ name;
}

bool hasHibernatedAnnotation(T, string m)() {
	foreach(a; __traits(getAttributes, __traits(getMember, T, m))) {
		static if (isHibernatedAnnotation!a) {
			return true;
		}
	}
	return false;
}

bool hasHibernatedEntityAnnotation(T)() {
	foreach(a; __traits(getAttributes, T)) {
		static if (isHibernatedEntityAnnotation!a) {
			return true;
		}
	}
	return false;
}

string getEntityName(T)() {
	foreach (a; __traits(getAttributes, T)) {
		static if (is(typeof(a) == Entity)) {
			return a.name;
		}
		static if (a.stringof == Entity.stringof) {
			return T.stringof;
		}
	}
	return T.stringof;
}

string getTableName(T)() {
	foreach (a; __traits(getAttributes, T)) {
		static if (is(typeof(a) == Table)) {
			return a.name;
		}
	}
	return toLower(T.stringof);
}

bool hasIdAnnotation(T, string m)() {
	foreach (a; __traits(getAttributes, __traits(getMember,T,m))) {
		static if (is(typeof(a) == Id)) {
			return true;
		}
		static if (a.stringof == Id.stringof) {
			return true;
		}
	}
	return false;
}

bool hasGeneratedAnnotation(T, string m)() {
	foreach (a; __traits(getAttributes, __traits(getMember,T,m))) {
		static if (is(typeof(a) == Generated)) {
			return true;
		}
		static if (a.stringof == Generated.stringof) {
			return true;
		}
	}
	return false;
}

string applyDefault(string s, string defaultValue) {
	return s != null && s.length > 0 ? s : defaultValue;
}

string getColumnName(T, string m)() {
	foreach (a; __traits(getAttributes, __traits(getMember,T,m))) {
		static if (is(typeof(a) == Column)) {
			return applyDefault(a.name, toLower(getPropertyName!(T,m)()));
		}
		static if (a.stringof == Column.stringof) {
			return toLower(getPropertyName!(T,m)());
		}
	}
	return toLower(m);
}

int getColumnLength(T, string m)() {
	foreach (a; __traits(getAttributes, __traits(getMember,T,m))) {
		static if (is(typeof(a) == Column)) {
			return a.length;
		}
	}
	return 0;
}

bool getColumnNullable(T, string m)() {
	foreach (a; __traits(getAttributes, __traits(getMember,T,m))) {
		static if (is(typeof(a) == Column)) {
			return a.nullable;
		}
	}
	return true;
}

bool getColumnUnique(T, string m)() {
	foreach (a; __traits(getAttributes, __traits(getMember,T,m))) {
		static if (is(typeof(a) == Column)) {
			return a.unique;
		}
	}
	return false;
}

string getPropertyName(T, string m)() {
	alias typeof(__traits(getMember, T, m)) ti;
	static if (is(ti == function)) {
		return getterNameToFieldName(m);
	}
	return m;
}

enum PropertyMemberKind : int {
	FIELD_MEMBER,    // int field;
	GETTER_MEMBER,   // getField() + setField() or isField() and setField()
	PROPERTY_MEMBER  // @property int field() { return _field; }
}

bool hasPercentSign(immutable string str) {
	foreach(ch; str) {
		if (ch == '%')
			return true;
	}
	return false;
}

int percentSignCount(immutable string str) {
    string res;
    foreach(ch; str) {
        if (ch == '%')
            res ~= "%";
    }
    return cast(int)res.length;
}

string substituteParam(immutable string fmt, immutable string value) {
	if (hasPercentSign(fmt))
		return format(fmt, value);
	else
		return fmt;
}

string substituteParamTwice(immutable string fmt, immutable string value) {
	immutable int paramCount = cast(int)percentSignCount(fmt);
    if (paramCount == 1)
        return format(fmt, value);
    else if (paramCount == 2)
        return format(fmt, value, value);
    else
        return fmt;
}

static immutable string[] PropertyMemberKind_ReadCode = [
	"entity.%s",
    "entity.%s()",
 	"entity.%s",
];

PropertyMemberKind getPropertyMemberKind(T, string m)() {
	alias typeof(__traits(getMember, T, m)) ti;
	static if (is(ti == function)) {
		static if (functionAttributes!ti & FunctionAttribute.property)
			return PropertyMemberKind.PROPERTY_MEMBER;
		else
			return PropertyMemberKind.GETTER_MEMBER;
	} else {
		return PropertyMemberKind.FIELD_MEMBER;
	}
}

enum PropertyMemberType : int {
	BYTE_TYPE,    // byte
	SHORT_TYPE,   // short
	INT_TYPE,     // int
	LONG_TYPE,    // long
	UBYTE_TYPE,   // ubyte
	USHORT_TYPE,  // ushort
	UINT_TYPE,    // uint
	ULONG_TYPE,   // ulong
	NULLABLE_BYTE_TYPE,  // Nullable!byte
	NULLABLE_SHORT_TYPE, // Nullable!short
	NULLABLE_INT_TYPE,   // Nullable!int
	NULLABLE_LONG_TYPE,  // Nullable!long
	NULLABLE_UBYTE_TYPE, // Nullable!ubyte
	NULLABLE_USHORT_TYPE,// Nullable!ushort
	NULLABLE_UINT_TYPE,  // Nullable!uint
	NULLABLE_ULONG_TYPE, // Nullable!ulong
	STRING_TYPE   // string
}

PropertyMemberType getPropertyMemberType(T, string m)() {
	alias typeof(__traits(getMember, T, m)) ti;
    static if (is(ti == function)) {
		assert (is(ti == function));
		static if (is(ReturnType!(ti) == byte)) {
			return PropertyMemberType.BYTE_TYPE;
		} else if (is(ReturnType!(ti) == short)) {
			return PropertyMemberType.SHORT_TYPE;
		} else if (is(ReturnType!(ti) == int)) {
			return PropertyMemberType.INT_TYPE;
		} else if (is(ReturnType!(ti) == long)) {
			return PropertyMemberType.LONG_TYPE;
		} else if (is(ReturnType!(ti) == ubyte)) {
			return PropertyMemberType.UBYTE_TYPE;
		} else if (is(ReturnType!(ti) == ushort)) {
			return PropertyMemberType.USHORT_TYPE;
		} else if (is(ReturnType!(ti) == uint)) {
			return PropertyMemberType.UINT_TYPE;
		} else if (is(ReturnType!(ti) == ulong)) {
			return PropertyMemberType.ULONG_TYPE;
		} else if (is(ReturnType!(ti) == Nullable!byte)) {
			return PropertyMemberType.NULLABLE_BYTE_TYPE;
		} else if (is(ReturnType!(ti) == Nullable!short)) {
			return PropertyMemberType.NULLABLE_SHORT_TYPE;
		} else if (is(ReturnType!(ti) == Nullable!int)) {
			return PropertyMemberType.NULLABLE_INT_TYPE;
		} else if (is(ReturnType!(ti) == Nullable!long)) {
			return PropertyMemberType.NULLABLE_LONG_TYPE;
		} else if (is(ReturnType!(ti) == Nullable!ubyte)) {
			return PropertyMemberType.NULLABLE_UBYTE_TYPE;
		} else if (is(ReturnType!(ti) == Nullable!ushort)) {
			return PropertyMemberType.NULLABLE_USHORT_TYPE;
		} else if (is(ReturnType!(ti) == Nullable!uint)) {
			return PropertyMemberType.NULLABLE_UINT_TYPE;
		} else if (is(ReturnType!(ti) == Nullable!ulong)) {
			return PropertyMemberType.NULLABLE_ULONG_TYPE;
		} else if (is(ReturnType!(ti) == string)) {
			return PropertyMemberType.STRING_TYPE;
		} else {
			assert (false, "Member " ~ m ~ " of class " ~ T.stringof ~ " has unsupported type " ~ ti.stringof);
		}
	} else if (is(ti == byte)) {
		return PropertyMemberType.BYTE_TYPE;
	} else if (is(ti == short)) {
		return PropertyMemberType.SHORT_TYPE;
	} else if (is(ti == int)) {
		return PropertyMemberType.INT_TYPE;
	} else if (is(ti == long)) {
		return PropertyMemberType.LONG_TYPE;
	} else if (is(ti == ubyte)) {
		return PropertyMemberType.UBYTE_TYPE;
	} else if (is(ti == ushort)) {
		return PropertyMemberType.USHORT_TYPE;
	} else if (is(ti == uint)) {
		return PropertyMemberType.UINT_TYPE;
	} else if (is(ti == ulong)) {
		return PropertyMemberType.ULONG_TYPE;
	} else if (is(ti == Nullable!byte)) {
		return PropertyMemberType.NULLABLE_BYTE_TYPE;
	} else if (is(ti == Nullable!short)) {
		return PropertyMemberType.NULLABLE_SHORT_TYPE;
	} else if (is(ti == Nullable!int)) {
		return PropertyMemberType.NULLABLE_INT_TYPE;
	} else if (is(ti == Nullable!long)) {
		return PropertyMemberType.NULLABLE_LONG_TYPE;
	} else if (is(ti == Nullable!ubyte)) {
		return PropertyMemberType.NULLABLE_UBYTE_TYPE;
	} else if (is(ti == Nullable!ushort)) {
		return PropertyMemberType.NULLABLE_USHORT_TYPE;
	} else if (is(ti == Nullable!uint)) {
		return PropertyMemberType.NULLABLE_UINT_TYPE;
	} else if (is(ti == Nullable!ulong)) {
		return PropertyMemberType.NULLABLE_ULONG_TYPE;
	} else if (is(ti == string)) {
		return PropertyMemberType.STRING_TYPE;
	} else {
		assert (false, "Member " ~ m ~ " of class " ~ T.stringof ~ " has unsupported type " ~ ti.stringof);
	}
	//static assert (false, "Member " ~ m ~ " of class " ~ T.stringof ~ " has unsupported type " ~ ti.stringof);
}


string getPropertyReadCode(T, string m)() {
	return substituteParam(PropertyMemberKind_ReadCode[getPropertyMemberKind!(T,m)()], m);
}

static immutable string[] ColumnTypeKeyIsSetCode = 
	[
	 "(%s != 0)", //BYTE_TYPE,    // byte
	 "(%s != 0)", //SHORT_TYPE,   // short
	 "(%s != 0)", //INT_TYPE,     // int
	 "(%s != 0)", //LONG_TYPE,    // long
	 "(%s != 0)", //UBYTE_TYPE,   // ubyte
	 "(%s != 0)", //USHORT_TYPE,  // ushort
	 "(%s != 0)", //UINT_TYPE,    // uint
	 "(%s != 0)", //ULONG_TYPE,   // ulong
	 "(!%s.isNull)", //NULLABLE_BYTE_TYPE,  // Nullable!byte
	 "(!%s.isNull)", //NULLABLE_SHORT_TYPE, // Nullable!short
	 "(!%s.isNull)", //NULLABLE_INT_TYPE,   // Nullable!int
	 "(!%s.isNull)", //NULLABLE_LONG_TYPE,  // Nullable!long
	 "(!%s.isNull)", //NULLABLE_UBYTE_TYPE, // Nullable!ubyte
	 "(!%s.isNull)", //NULLABLE_USHORT_TYPE,// Nullable!ushort
	 "(!%s.isNull)", //NULLABLE_UINT_TYPE,  // Nullable!uint
	 "(!%s.isNull)", //NULLABLE_ULONG_TYPE, // Nullable!ulong
	 "(%s !is null)", //STRING_TYPE   // string
	 ];

string getColumnTypeKeyIsSetCode(T, string m)() {
	return substituteParam(ColumnTypeKeyIsSetCode[getPropertyMemberType!(T,m)()], getPropertyReadCode!(T,m)());
}

static immutable string[] ColumnTypeIsNullCode = 
	[
	 "(false)", //BYTE_TYPE,    // byte
	 "(false)", //SHORT_TYPE,   // short
	 "(false)", //INT_TYPE,     // int
	 "(false)", //LONG_TYPE,    // long
	 "(false)", //UBYTE_TYPE,   // ubyte
	 "(false)", //USHORT_TYPE,  // ushort
	 "(false)", //UINT_TYPE,    // uint
	 "(false)", //ULONG_TYPE,   // ulong
	 "(%s.isNull)", //NULLABLE_BYTE_TYPE,  // Nullable!byte
	 "(%s.isNull)", //NULLABLE_SHORT_TYPE, // Nullable!short
	 "(%s.isNull)", //NULLABLE_INT_TYPE,   // Nullable!int
	 "(%s.isNull)", //NULLABLE_LONG_TYPE,  // Nullable!long
	 "(%s.isNull)", //NULLABLE_UBYTE_TYPE, // Nullable!ubyte
	 "(%s.isNull)", //NULLABLE_USHORT_TYPE,// Nullable!ushort
	 "(%s.isNull)", //NULLABLE_UINT_TYPE,  // Nullable!uint
	 "(%s.isNull)", //NULLABLE_ULONG_TYPE, // Nullable!ulong
	 "(%s is null)", //STRING_TYPE   // string
	 ];

string getColumnTypeIsNullCode(T, string m)() {
	return substituteParam(ColumnTypeIsNullCode[getPropertyMemberType!(T,m)()], getPropertyReadCode!(T,m)());
}

static immutable string[] ColumnTypeSetNullCode = 
	[
	 "byte nv = 0;", //BYTE_TYPE,    // byte
	 "short nv = 0;", //SHORT_TYPE,   // short
	 "int nv = 0;", //INT_TYPE,     // int
	 "long nv = 0;", //LONG_TYPE,    // long
	 "ubyte nv = 0;", //UBYTE_TYPE,   // ubyte
	 "ushort nv = 0;", //USHORT_TYPE,  // ushort
	 "uint nv = 0;", //UINT_TYPE,    // uint
	 "ulong nv = 0;", //ULONG_TYPE,   // ulong
	 "Nullable!byte nv;", //NULLABLE_BYTE_TYPE,  // Nullable!byte
	 "Nullable!short nv;", //NULLABLE_SHORT_TYPE, // Nullable!short
	 "Nullable!int nv;", //NULLABLE_INT_TYPE,   // Nullable!int
	 "Nullable!long nv;", //NULLABLE_LONG_TYPE,  // Nullable!long
	 "Nullable!ubyte nv;", //NULLABLE_UBYTE_TYPE, // Nullable!ubyte
	 "Nullable!ushort nv;", //NULLABLE_USHORT_TYPE,// Nullable!ushort
	 "Nullable!uint nv;", //NULLABLE_UINT_TYPE,  // Nullable!uint
	 "Nullable!ulong nv;", //NULLABLE_ULONG_TYPE, // Nullable!ulong
	 "string nv = null;", //STRING_TYPE   // string
	 ];

static immutable string[] ColumnTypePropertyToVariant = 
    [
     "Variant(%s)", //BYTE_TYPE,    // byte
     "Variant(%s)", //SHORT_TYPE,   // short
     "Variant(%s)", //INT_TYPE,     // int
     "Variant(%s)", //LONG_TYPE,    // long
     "Variant(%s)", //UBYTE_TYPE,   // ubyte
     "Variant(%s)", //USHORT_TYPE,  // ushort
     "Variant(%s)", //UINT_TYPE,    // uint
     "Variant(%s)", //ULONG_TYPE,   // ulong
     "(%s.isNull ? Variant(null) : Variant(%s.get()))", //NULLABLE_BYTE_TYPE,  // Nullable!byte
     "(%s.isNull ? Variant(null) : Variant(%s.get()))", //NULLABLE_SHORT_TYPE, // Nullable!short
     "(%s.isNull ? Variant(null) : Variant(%s.get()))", //NULLABLE_INT_TYPE,   // Nullable!int
     "(%s.isNull ? Variant(null) : Variant(%s.get()))", //NULLABLE_LONG_TYPE,  // Nullable!long
     "(%s.isNull ? Variant(null) : Variant(%s.get()))", //NULLABLE_UBYTE_TYPE, // Nullable!ubyte
     "(%s.isNull ? Variant(null) : Variant(%s.get()))", //NULLABLE_USHORT_TYPE,// Nullable!ushort
     "(%s.isNull ? Variant(null) : Variant(%s.get()))", //NULLABLE_UINT_TYPE,  // Nullable!uint
     "(%s.isNull ? Variant(null) : Variant(%s.get()))", //NULLABLE_ULONG_TYPE, // Nullable!ulong
     "Variant(%s)", //STRING_TYPE   // string
     ];

string getPropertyWriteCode(T, string m)() {
	immutable PropertyMemberKind kind = getPropertyMemberKind!(T, m)();
	immutable string nullValueCode = ColumnTypeSetNullCode[getPropertyMemberType!(T,m)()];
	immutable string datasetReader = "(!r.isNull(index) ? " ~ getColumnTypeDatasetReadCode!(T, m)() ~ " : nv)";
	static if (kind == PropertyMemberKind.FIELD_MEMBER) {
		return nullValueCode ~ "entity." ~ m ~ " = " ~ datasetReader ~ ";";
	} else if (kind == PropertyMemberKind.GETTER_MEMBER) {
		return nullValueCode ~ "entity." ~ getterNameToSetterName(m) ~ "(" ~ datasetReader ~ ");";
	} else if (kind == PropertyMemberKind.PROPERTY_MEMBER) {
		return nullValueCode ~ "entity." ~ m ~ " = " ~ datasetReader ~ ";";
	} else {
		assert(0);
	}
}

string getPropertyVariantWriteCode(T, string m)() {
	immutable memberType = getPropertyMemberType!(T,m)();
	immutable string nullValueCode = ColumnTypeSetNullCode[memberType];
	immutable string variantReadCode = ColumnTypeVariantReadCode[memberType];
	static if (getPropertyMemberKind!(T, m)() == PropertyMemberKind.GETTER_MEMBER) {
		return nullValueCode ~ "entity." ~ getterNameToSetterName(m) ~ "(" ~ variantReadCode ~ ");";
	} else {
		return nullValueCode ~ "entity." ~ m ~ " = " ~ variantReadCode ~ ";";
	}
}

string getPropertyVariantReadCode(T, string m)() {
    immutable memberType = getPropertyMemberType!(T,m)();
    immutable string propertyReadCode = getPropertyReadCode!(T,m)();
    return substituteParamTwice(ColumnTypePropertyToVariant[memberType], propertyReadCode);
}

static immutable string[] ColumnTypeConstructorCode = 
	[
	 "new IntegerType()", //BYTE_TYPE,    // byte
	 "new IntegerType()", //SHORT_TYPE,   // short
	 "new IntegerType()", //INT_TYPE,     // int
	 "new BigIntegerType()", //LONG_TYPE,    // long
	 "new IntegerType()", //UBYTE_TYPE,   // ubyte
	 "new IntegerType()", //USHORT_TYPE,  // ushort
	 "new IntegerType()", //UINT_TYPE,    // uint
	 "new BigIntegerType()", //ULONG_TYPE,   // ulong
	 "new IntegerType()", //NULLABLE_BYTE_TYPE,  // Nullable!byte
	 "new IntegerType()", //NULLABLE_SHORT_TYPE, // Nullable!short
	 "new IntegerType()", //NULLABLE_INT_TYPE,   // Nullable!int
	 "new BigIntegerType()", //NULLABLE_LONG_TYPE,  // Nullable!long
	 "new IntegerType()", //NULLABLE_UBYTE_TYPE, // Nullable!ubyte
	 "new IntegerType()", //NULLABLE_USHORT_TYPE,// Nullable!ushort
	 "new IntegerType()", //NULLABLE_UINT_TYPE,  // Nullable!uint
	 "new BigIntegerType()", //NULLABLE_ULONG_TYPE, // Nullable!ulong
	 "new StringType()", //STRING_TYPE   // string
	 ];

string getColumnTypeName(T, string m)() {
	return ColumnTypeConstructorCode[getPropertyMemberType!(T,m)()];
}

static immutable string[] ColumnTypeDatasetReaderCode = 
	[
	 "r.getByte(index)", //BYTE_TYPE,    // byte
	 "r.getShort(index)", //SHORT_TYPE,   // short
	 "r.getInt(index)", //INT_TYPE,     // int
	 "r.getLong(index)", //LONG_TYPE,    // long
	 "r.getUbyte(index)", //UBYTE_TYPE,   // ubyte
	 "r.getUshort(index)", //USHORT_TYPE,  // ushort
	 "r.getUint(index)", //UINT_TYPE,    // uint
	 "r.getUlong(index)", //ULONG_TYPE,   // ulong
	 "Nullable!byte(r.getByte(index))", //NULLABLE_BYTE_TYPE,  // Nullable!byte
     "Nullable!short(r.getShort(index))", //NULLABLE_SHORT_TYPE, // Nullable!short
     "Nullable!int(r.getInt(index))", //NULLABLE_INT_TYPE,   // Nullable!int
     "Nullable!long(r.getLong(index))", //NULLABLE_LONG_TYPE,  // Nullable!long
     "Nullable!ubyte(r.getUbyte(index))", //NULLABLE_UBYTE_TYPE, // Nullable!ubyte
     "Nullable!ushort(r.getUshort(index))", //NULLABLE_USHORT_TYPE,// Nullable!ushort
     "Nullable!uint(r.getUint(index))", //NULLABLE_UINT_TYPE,  // Nullable!uint
     "Nullable!ulong(r.getUlong(index))", //NULLABLE_ULONG_TYPE, // Nullable!ulong
	 "r.getString(index)", //STRING_TYPE   // string
	 ];

string getColumnTypeDatasetReadCode(T, string m)() {
	return ColumnTypeDatasetReaderCode[getPropertyMemberType!(T,m)()];
}

static immutable string[] ColumnTypeVariantReadCode = 
	[
	 "(value == null ? nv : (value.convertsTo!(byte) ? value.get!(byte) : (value.convertsTo!(long) ? to!byte(value.get!(long)) : to!byte((value.get!(ulong))))))", //BYTE_TYPE,    // byte
	 "(value == null ? nv : (value.convertsTo!(shirt) ? value.get!(short) : (value.convertsTo!(long) ? to!short(value.get!(long)) : to!short((value.get!(ulong))))))", //SHORT_TYPE,   // short
	 "(value == null ? nv : (value.convertsTo!(int) ? value.get!(int) : (value.convertsTo!(long) ? to!int(value.get!(long)) : to!int((value.get!(ulong))))))", //INT_TYPE,     // int
	 "(value == null ? nv : (value.convertsTo!(long) ? value.get!(long) : to!long(value.get!(ulong))))", //LONG_TYPE,    // long
	 "(value == null ? nv : (value.convertsTo!(ubyte) ? value.get!(ubyte) : (value.convertsTo!(ulong) ? to!ubyte(value.get!(ulong)) : to!ubyte((value.get!(long))))))", //UBYTE_TYPE,   // ubyte
	 "(value == null ? nv : (value.convertsTo!(ushort) ? value.get!(ushort) : (value.convertsTo!(ulong) ? to!ushort(value.get!(ulong)) : to!ushort((value.get!(long))))))", //USHORT_TYPE,  // ushort
	 "(value == null ? nv : (value.convertsTo!(uint) ? value.get!(uint) : (value.convertsTo!(ulong) ? to!uint(value.get!(ulong)) : to!uint((value.get!(long))))))", //UINT_TYPE,    // uint
	 "(value == null ? nv : (value.convertsTo!(ulong) ? value.get!(ulong) : to!ulong(value.get!(long))))", //ULONG_TYPE,   // ulong
	 "(value == null ? nv : (value.convertsTo!(byte) ? value.get!(byte) : (value.convertsTo!(long) ? to!byte(value.get!(long)) : to!byte((value.get!(ulong))))))", //NULLABLE_BYTE_TYPE,  // Nullable!byte
	 "(value == null ? nv : (value.convertsTo!(shirt) ? value.get!(short) : (value.convertsTo!(long) ? to!short(value.get!(long)) : to!short((value.get!(ulong))))))", //NULLABLE_SHORT_TYPE, // Nullable!short
	 "(value == null ? nv : (value.convertsTo!(int) ? value.get!(int) : (value.convertsTo!(long) ? to!int(value.get!(long)) : to!int((value.get!(ulong))))))", //NULLABLE_INT_TYPE,   // Nullable!int
	 "(value == null ? nv : (value.convertsTo!(long) ? value.get!(long) : to!long(value.get!(ulong))))", //NULLABLE_LONG_TYPE,  // Nullable!long
	 "(value == null ? nv : (value.convertsTo!(ubyte) ? value.get!(ubyte) : (value.convertsTo!(ulong) ? to!ubyte(value.get!(ulong)) : to!ubyte((value.get!(long))))))", //NULLABLE_UBYTE_TYPE, // Nullable!ubyte
	 "(value == null ? nv : (value.convertsTo!(ushort) ? value.get!(ushort) : (value.convertsTo!(ulong) ? to!ushort(value.get!(ulong)) : to!ushort((value.get!(long))))))", //NULLABLE_USHORT_TYPE,// Nullable!ushort
	 "(value == null ? nv : (value.convertsTo!(uint) ? value.get!(uint) : (value.convertsTo!(ulong) ? to!uint(value.get!(ulong)) : to!uint((value.get!(long))))))", //NULLABLE_UINT_TYPE,  // Nullable!uint
	 "(value == null ? nv : (value.convertsTo!(ulong) ? value.get!(ulong) : to!ulong(value.get!(long))))", //NULLABLE_ULONG_TYPE, // Nullable!ulong
	 "(value == null ? nv : value.get!(string))", //STRING_TYPE   // string
	 ];

static immutable string[] DatasetWriteCode = 
	[
	 "r.setByte(index, %s);", //BYTE_TYPE,    // byte
	 "r.setShort(index, %s);", //SHORT_TYPE,   // short
	 "r.setInt(index, %s);", //INT_TYPE,     // int
	 "r.setLong(index, %s);", //LONG_TYPE,    // long
	 "r.setUbyte(index, %s);", //UBYTE_TYPE,   // ubyte
	 "r.setUshort(index, %s);", //USHORT_TYPE,  // ushort
	 "r.setUint(index, %s);", //UINT_TYPE,    // uint
	 "r.setUlong(index, %s);", //ULONG_TYPE,   // ulong
	 "r.setByte(index, %s);", //NULLABLE_BYTE_TYPE,  // Nullable!byte
	 "r.setShort(index, %s);", //NULLABLE_SHORT_TYPE, // Nullable!short
	 "r.setInt(index, %s);", //NULLABLE_INT_TYPE,   // Nullable!int
	 "r.setLong(index, %s);", //NULLABLE_LONG_TYPE,  // Nullable!long
	 "r.setUbyte(index, %s);", //NULLABLE_UBYTE_TYPE, // Nullable!ubyte
	 "r.setUshort(index, %s);", //NULLABLE_USHORT_TYPE,// Nullable!ushort
	 "r.setUint(index, %s);", //NULLABLE_UINT_TYPE,  // Nullable!uint
	 "r.setUlong(index, %s);", //NULLABLE_ULONG_TYPE, // Nullable!ulong
	 "r.setString(index, %s);", //STRING_TYPE   // string
	 ];

string getColumnTypeDatasetWriteCode(T, string m)() {
	alias typeof(__traits(getMember, T, m)) ti;
	immutable string isNullCode = getColumnTypeIsNullCode!(T,m)();
	immutable string readCode = getPropertyReadCode!(T,m)();
	immutable string setDataCode = DatasetWriteCode[getPropertyMemberType!(T,m)()];
	return "if (" ~ isNullCode ~ ") r.setNull(index); else " ~ substituteParam(setDataCode, readCode);
}

string getPropertyDef(T, immutable string m)() {
	immutable string entityClassName = fullyQualifiedName!T;
	immutable string propertyName = getPropertyName!(T,m)();
	static assert (propertyName != null, "Cannot determine property name for member " ~ m ~ " of type " ~ T.stringof);
	immutable bool isId = hasIdAnnotation!(T, m)();
	immutable bool isGenerated = hasGeneratedAnnotation!(T, m)();
	immutable string columnName = getColumnName!(T, m)();
	immutable length = getColumnLength!(T, m)();
	immutable bool nullable = getColumnNullable!(T, m)();
	immutable bool unique = getColumnUnique!(T, m)();
	immutable string typeName = getColumnTypeName!(T, m)();
	immutable string propertyReadCode = getPropertyReadCode!(T,m)();
	immutable string datasetReadCode = getColumnTypeDatasetReadCode!(T,m)();
	immutable string propertyWriteCode = getPropertyWriteCode!(T,m)();
	immutable string datasetWriteCode = getColumnTypeDatasetWriteCode!(T,m)();
	immutable string propertyVariantSetCode = getPropertyVariantWriteCode!(T,m)();
    immutable string propertyVariantGetCode = getPropertyVariantReadCode!(T,m)();
	immutable string keyIsSetCode = getColumnTypeKeyIsSetCode!(T,m)();
	immutable string isNullCode = getColumnTypeIsNullCode!(T,m)();
	immutable string readerFuncDef = "\n" ~
		"function(Object obj, DataSetReader r, int index) { \n" ~ 
		"    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
			"    " ~ propertyWriteCode ~ " \n" ~
		" }\n";
	immutable string writerFuncDef = "\n" ~
		"function(Object obj, DataSetWriter r, int index) { \n" ~ 
			"    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
			"    " ~ datasetWriteCode ~ " \n" ~
			" }\n";
	immutable string getVariantFuncDef = "\n" ~
		"function(Object obj) { \n" ~ 
			"    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
            "    return " ~ propertyVariantGetCode ~ "; \n" ~
			" }\n";
	immutable string setVariantFuncDef = "\n" ~
		"function(Object obj, Variant value) { \n" ~ 
			"    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
			"    " ~ propertyVariantSetCode ~ "\n" ~
			" }\n";
	immutable string keyIsSetFuncDef = "\n" ~
		"function(Object obj) { \n" ~ 
			"    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
			"    return " ~ keyIsSetCode ~ ";\n" ~
			" }\n";
	immutable string isNullFuncDef = "\n" ~
		"function(Object obj) { \n" ~ 
			"    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
			"    return " ~ isNullCode ~ ";\n" ~
			" }\n";

//	pragma(msg, propertyReadCode);
//	pragma(msg, datasetReadCode);
//	pragma(msg, propertyWriteCode);
//	pragma(msg, datasetWriteCode);
//	pragma(msg, readerFuncDef);
//	pragma(msg, writerFuncDef);

	static assert (typeName != null, "Cannot determine column type for member " ~ m ~ " of type " ~ T.stringof);
	return "    new PropertyInfo(\"" ~ propertyName ~ "\", \"" ~ columnName ~ "\", " ~ typeName ~ ", " ~ 
			format("%s",length) ~ ", " ~ (isId ? "true" : "false")  ~ ", " ~ 
			(isGenerated ? "true" : "false")  ~ ", " ~ (nullable ? "true" : "false") ~ ", " ~ 
			readerFuncDef ~ ", " ~
			writerFuncDef ~ ", " ~
			getVariantFuncDef ~ ", " ~
			setVariantFuncDef ~ ", " ~
			keyIsSetFuncDef ~ ", " ~
			isNullFuncDef ~
			")";
}

string getEntityDef(T)() {
	string res;
	string generatedGettersSetters;

	string generatedEntityInfo;
	string generatedPropertyInfo;

    immutable string typeName = fullyQualifiedName!T;

	static assert (hasHibernatedEntityAnnotation!T(), "Type " ~ typeName ~ " has no Entity annotation");
    pragma(msg, "Entity type name: " ~ typeName);

	immutable string entityName = getEntityName!T();
	immutable string tableName = getTableName!T();

	static assert (entityName != null, "Type " ~ typeName ~ " has no Entity name specified");
	static assert (tableName != null, "Type " ~ typeName ~ " has no Table name specified");

	generatedEntityInfo ~= "new EntityInfo(";
	generatedEntityInfo ~= "\"" ~ entityName ~ "\", ";
	generatedEntityInfo ~= "\"" ~ tableName ~ "\", ";
	generatedEntityInfo ~= "[\n";

	foreach (m; __traits(allMembers, T)) {
		//pragma(msg, m);

		static if (__traits(compiles, (typeof(__traits(getMember, T, m))))){
			
//			static if (hasHibernatedAnnotation!(T, m)) {
//				pragma(msg, "Member " ~ m ~ " has known annotation");
//			}

			alias typeof(__traits(getMember, T, m)) ti;


			static if (hasHibernatedAnnotation!(T, m)) {
				
				immutable string propertyDef = getPropertyDef!(T, m)();
				//pragma(msg, propertyDef);

				if (generatedPropertyInfo != null)
					generatedPropertyInfo ~= ",\n";
				generatedPropertyInfo ~= propertyDef;
			}
		}
	}
	//pragma(msg, t);
	//pragma(msg, typeof(t));

	generatedEntityInfo ~= generatedPropertyInfo;
	generatedEntityInfo ~= "],";
	generatedEntityInfo ~= "" ~ typeName ~ ".classinfo";
	generatedEntityInfo ~= ")";

	return generatedEntityInfo ~ "\n" ~ generatedGettersSetters;
}


string entityListDef(T ...)() {
	string res;
	foreach(t; T) {
		immutable string def = getEntityDef!t;

        pragma(msg, def);

		if (res.length > 0)
			res ~= ",\n";
		res ~= def;
	}
	string code = 
		"static this() {\n" ~
		"    entities = [\n" ~ res ~ "];\n" ~
		"    EntityInfo [string] map;\n" ~
		"    EntityInfo [TypeInfo_Class] typemap;\n" ~
		"    foreach(e; entities) {\n" ~
		"        map[e.name] = e;\n" ~
		"        typemap[cast(TypeInfo_Class)e.classInfo] = e;\n" ~
		"    }\n" ~
		"    entityMap = map;\n" ~
		"    classMap = typemap;\n" ~
		"}";
    return code;
}

interface EntityMetaData {
    public EntityInfo [] getEntities();
    public EntityInfo [string] getEntityMap();
    public EntityInfo [TypeInfo_Class] getClassMap();
    public EntityInfo findEntity(string entityName);
    public EntityInfo findEntity(TypeInfo_Class entityClass);
    public EntityInfo findEntityForObject(Object obj);
    public EntityInfo getEntity(int entityIndex);
    public int getEntityCount();
	public Object createEntity(string entityName);
    public void readAllColumns(Object obj, DataSetReader r, int startColumn);
	public void writeAllColumns(Object obj, DataSetWriter w, int startColumn);
	public void writeAllColumnsExceptKey(Object obj, DataSetWriter w, int startColumn);
	public string generateFindAllForEntity(string entityName);
    public string getAllFieldList(EntityInfo ei);
    public string getAllFieldList(string entityName);
    public string generateFindByPkForEntity(EntityInfo ei);
    public string generateFindByPkForEntity(string entityName);
	public string generateInsertAllFieldsForEntity(EntityInfo ei);
	public string generateInsertAllFieldsForEntity(string entityName);
	public string generateInsertNoKeyForEntity(EntityInfo ei);
	public string generateUpdateForEntity(EntityInfo ei);
	public Variant getPropertyValue(Object obj, string propertyName);
    public void setPropertyValue(Object obj, string propertyName, Variant value);
}

abstract class SchemaInfo : EntityMetaData {

    override public Variant getPropertyValue(Object obj, string propertyName) {
        return findEntityForObject(obj).getPropertyValue(obj, propertyName);
    }

    override public void setPropertyValue(Object obj, string propertyName, Variant value) {
        findEntityForObject(obj).setPropertyValue(obj, propertyName, value);
    }


    public string getAllFieldList(EntityInfo ei) {
        string query;
        for (int i = 0; i < ei.getPropertyCount(); i++) {
            if (query.length != 0)
                query ~= ", ";
            query ~= ei.getProperty(i).columnName;
        }
        return query;
    }

	public string getAllFieldListExceptKeyForUpdate(EntityInfo ei) {
		string query;
		for (int i = 0; i < ei.getPropertyCount(); i++) {
			if (ei.getProperty(i).key)
				continue;
			if (query.length != 0)
				query ~= ", ";
			query ~= ei.getProperty(i).columnName;
			query ~= "=?";
		}
		return query;
	}
	
	public string getAllFieldListExceptKey(EntityInfo ei) {
		string query;
		for (int i = 0; i < ei.getPropertyCount(); i++) {
			if (ei.getProperty(i).key)
				continue;
			if (query.length != 0)
				query ~= ", ";
			query ~= ei.getProperty(i).columnName;
		}
		return query;
	}
	
	public string getAllFieldPlaceholderList(EntityInfo ei) {
		string query;
		for (int i = 0; i < ei.getPropertyCount(); i++) {
			if (query.length != 0)
				query ~= ", ";
			query ~= '?';
		}
		return query;
	}
	
	public string getAllFieldPlaceholderListExceptKey(EntityInfo ei) {
		string query;
		for (int i = 0; i < ei.getPropertyCount(); i++) {
			if (ei.getProperty(i).key)
				continue;
			if (query.length != 0)
				query ~= ", ";
			query ~= '?';
		}
		return query;
	}
	
	public string getAllFieldList(string entityName) {
        return getAllFieldList(findEntity(entityName));
    }

    public void readAllColumns(Object obj, DataSetReader r, int startColumn) {
		EntityInfo ei = findEntityForObject(obj);
		for (int i = 0; i<ei.getPropertyCount(); i++) {
			ei.getProperty(i).readFunc(obj, r, startColumn + i);
		}
	}

	public void writeAllColumns(Object obj, DataSetWriter w, int startColumn) {
		EntityInfo ei = findEntityForObject(obj);
		for (int i = 0; i<ei.getPropertyCount(); i++) {
			ei.getProperty(i).writeFunc(obj, w, startColumn + i);
		}
	}

	public void writeAllColumnsExceptKey(Object obj, DataSetWriter w, int startColumn) {
		EntityInfo ei = findEntityForObject(obj);
		int index = 0;
		for (int i = 0; i<ei.getPropertyCount(); i++) {
			if (ei.getProperty(i).key)
				continue;
			ei.getProperty(i).writeFunc(obj, w, startColumn + index);
			index++;
		}
	}

    public string generateFindAllForEntity(string entityName) {
		EntityInfo ei = findEntity(entityName);
        return "SELECT " ~ getAllFieldList(ei) ~ " FROM " ~ ei.tableName;
	}

    public string generateFindByPkForEntity(EntityInfo ei) {
        return "SELECT " ~ getAllFieldList(ei) ~ " FROM " ~ ei.tableName ~ " WHERE " ~ ei.keyProperty.columnName ~ " = ?";
    }

	public string generateInsertAllFieldsForEntity(EntityInfo ei) {
		return "INSERT INTO " ~ ei.tableName ~ "(" ~ getAllFieldList(ei) ~ ") VALUES (" ~ getAllFieldPlaceholderList(ei) ~ ")";
	}

	public string generateInsertNoKeyForEntity(EntityInfo ei) {
		return "INSERT INTO " ~ ei.tableName ~ "(" ~ getAllFieldListExceptKey(ei) ~ ") VALUES (" ~ getAllFieldPlaceholderListExceptKey(ei) ~ ")";
	}

	public string generateUpdateForEntity(EntityInfo ei) {
		return "UPDATE " ~ ei.tableName ~ " SET " ~ getAllFieldListExceptKeyForUpdate(ei) ~ " WHERE " ~ ei.getKeyProperty().columnName ~ "=?";
	}

	public string generateFindByPkForEntity(string entityName) {
        return generateFindByPkForEntity(findEntity(entityName));
    }

	public string generateInsertAllFieldsForEntity(string entityName){
		return generateInsertAllFieldsForEntity(findEntity(entityName));
	}
}

class SchemaInfoImpl(T...) : SchemaInfo {
	static EntityInfo [string] entityMap;
	static EntityInfo [] entities;
	static EntityInfo [TypeInfo_Class] classMap;
    pragma(msg, entityListDef!(T)());
    mixin(entityListDef!(T)());

    public int getEntityCount()  { return cast(int)entities.length; }

    public EntityInfo[] getEntities()  { return entities; }
	public EntityInfo[string] getEntityMap()  { return entityMap; }
    public EntityInfo [TypeInfo_Class] getClassMap() { return classMap; }

    public EntityInfo findEntity(string entityName)  { 
        try {
            return entityMap[entityName]; 
        } catch (Exception e) {
            throw new HibernatedException("Cannot find entity by name " ~ entityName);
        }
    }
    public EntityInfo findEntity(TypeInfo_Class entityClass) { 
        try {
            return classMap[entityClass]; 
        } catch (Exception e) {
            throw new HibernatedException("Cannot find entity by class " ~ entityClass.toString());
        }
    }
    public EntityInfo getEntity(int entityIndex) { 
        try {
            return entities[entityIndex]; 
        } catch (Exception e) {
            throw new HibernatedException("Cannot get entity by index " ~ to!string(entityIndex));
        }
    }
    public Object createEntity(string entityName) { 
        try {
            return entityMap[entityName].createEntity(); 
        } catch (Exception e) {
            throw new HibernatedException("Cannot find entity by name " ~ entityName);
        }
    }
    public EntityInfo findEntityForObject(Object obj) {
        try {
            return classMap[obj.classinfo];
        } catch (Exception e) {
            throw new HibernatedException("Cannot find entity metadata for " ~ obj.classinfo.toString());
        }
    }
}


unittest {

	@Entity
	@Table("users")
	static class User {
		
		@Id @Generated
		@Column("id_column")
		int id;
		
		@Column("name_column")
		string name;
		
		// no column name
		@Column
		string flags;
		
		// annotated getter
		private string login;
		@Column
		public string getLogin() { return login; }
		public void setLogin(string login) { this.login = login; }
		
		// no (), no column name
		@Column
		int testColumn;
	}
	
	
	@Entity
	@Table("customer")
	static class Customer {
		@Id @Generated
		@Column
		int id;
		@Column
		string name;
	}

	EntityInfo entity = new EntityInfo("user", "users",  [
	                                                      new PropertyInfo("id", "id", new IntegerType(), 0, true, true, false, null, null, null, null, null, null)
	                                                     ], null);

	assert(entity.properties.length == 1);


//	immutable string info = getEntityDef!User();
//	immutable string infos = entityListDef!(User, Customer)();

	EntityInfo ei = new EntityInfo("User", "users", [
	                                                 new PropertyInfo("id", "id_column", new IntegerType(), 0, true, true, false, null, null, null, null, null, null),
	                                                 new PropertyInfo("name", "name_column", new StringType(), 0, false, false, false, null, null, null, null, null, null),
	                                                 new PropertyInfo("flags", "flags", new StringType(), 0, false, false, true, null, null, null, null, null, null),
	                                                 new PropertyInfo("login", "login", new StringType(), 0, false, false, true, null, null, null, null, null, null),
	                                                 new PropertyInfo("testColumn", "testcolumn", new IntegerType(), 0, false, false, true, null, null, null, null, null, null)], null);

	//void function(User, DataSetReader, int) readFunc = function(User entity, DataSetReader reader, int index) { };

	assert(ei.findProperty("name").columnName == "name_column");
	assert(ei.getProperties()[0].columnName == "id_column");
	assert(ei.getProperty(2).propertyName == "flags");
	assert(ei.getPropertyCount == 5);

	EntityInfo[] entities3 =  [
	                                                                 new EntityInfo("User", "users", [
	                                 new PropertyInfo("id", "id_column", new IntegerType(), 0, true, true, false, null, null, null, null, null, null),
	                                 new PropertyInfo("name", "name_column", new StringType(), 0, false, false, false, null, null, null, null, null, null),
	                                 new PropertyInfo("flags", "flags", new StringType(), 0, false, false, true, null, null, null, null, null, null),
	                                 new PropertyInfo("login", "login", new StringType(), 0, false, false, true, null, null, null, null, null, null),
	                                 new PropertyInfo("testColumn", "testcolumn", new IntegerType(), 0, false, false, true, null, null, null, null, null, null)], null)
	                                                                 ,
	                                                                 new EntityInfo("Customer", "customer", [
	                                        new PropertyInfo("id", "id", new IntegerType(), 0, true, true, true, null, null, null, null, null, null),
	                                        new PropertyInfo("name", "name", new StringType(), 0, false, false, true, null, null, null, null, null, null)], null)
	                                                                 ];


}


version(unittest) {
    @Entity
    @Table("users")
    class User {
        
        @Id @Generated
        @Column("id")
        long id;
        
        @Column("name")
        string name;

        // property column
        private long _flags;
        @Column
        @property long flags() { return _flags; }
        @property void flags(long v) { _flags = v; }
        
        // getter/setter property
        string comment;
        @Column
        string getComment() { return comment; }
        void setComment(string v) { comment = v; }

        // long column which can hold NULL value
        @Column("customer_fk")
        Nullable!long customerId;

        override string toString() {
            return "id=" ~ to!string(id) ~ ", name=" ~ name ~ ", flags=" ~ to!string(flags) ~ ", comment=" ~ comment ~ ", customerId=" ~ (customerId.isNull ? "NULL" : to!string(customerId));
        }

    }
    
    
    @Entity
    @Table("customers")
    class Customer {
        @Id @Generated
        @Column
        int id;
        @Column
        string name;
    }
    
    @Entity
    @Table("t1")
    class T1 {
        @Id @Generated
        @Column
        int id;

        @Column
        string name;

        // property column
        private long _flags;
        @Column
        @property long flags() { return _flags; }
        @property void flags(long v) { _flags = v; }

        // getter/setter property
        string comment;
        @Column
        string getComment() { return comment; }
        void setComment(string v) { comment = v; }


        override string toString() {
            return "id=" ~ to!string(id) ~ ", name=" ~ name ~ ", flags=" ~ to!string(flags) ~ ", comment=" ~ comment;
        }
    }

	import ddbc.drivers.mysqlddbc;
	import ddbc.common;


    string[] UNIT_TEST_DROP_TABLES_SCRIPT = 
        [
         "DROP TABLE IF EXISTS users",
         "DROP TABLE IF EXISTS customers",
         ];
    string[] UNIT_TEST_CREATE_TABLES_SCRIPT = 
	[
         "CREATE TABLE IF NOT EXISTS users (id BIGINT NOT NULL PRIMARY KEY AUTO_INCREMENT, name VARCHAR(255) NOT NULL, flags INT, comment TEXT, customer_fk BIGINT NULL)",
         "CREATE TABLE IF NOT EXISTS customers (id BIGINT NOT NULL PRIMARY KEY AUTO_INCREMENT, name VARCHAR(255) NOT NULL)",
         "INSERT INTO customers SET id=1, name='customer 1'",
         "INSERT INTO customers SET id=2, name='customer 2'",
         "INSERT INTO customers SET id=3, name='customer 3'",
         "INSERT INTO users SET id=1, name='user 1', flags=11,   comment='comments for user 1', customer_fk=1",
         "INSERT INTO users SET id=2, name='user 2', flags=22,   comment='this user belongs to customer 1', customer_fk=1",
         "INSERT INTO users SET id=3, name='user 3', flags=NULL, comment='this user belongs to customer 2', customer_fk=2",
         "INSERT INTO users SET id=4, name='user 4', flags=44,   comment=NULL, customer_fk=3",
         "INSERT INTO users SET id=5, name='test user 5', flags=55,   comment='this user belongs to customer 3, too', customer_fk=3",
		 "INSERT INTO users SET id=6, name='test user 6', flags=66,   comment='for checking of Nullable!long reading', customer_fk=null",
         ];

    void recreateTestSchema() {
        DataSource connectionPool = createUnitTestMySQLDataSource();
		Connection conn = connectionPool.getConnection();
		scope(exit) conn.close();
        unitTestExecuteBatch(conn, UNIT_TEST_DROP_TABLES_SCRIPT);
        unitTestExecuteBatch(conn, UNIT_TEST_CREATE_TABLES_SCRIPT);
	}

}


unittest {

	// Checking generated metadata
	EntityMetaData schema = new SchemaInfoImpl!(User, Customer);

	assert(schema.getEntityCount() == 2);
	assert(schema.findEntity("User").findProperty("name").columnName == "name");
	assert(schema.findEntity("User").getProperties()[0].columnName == "id");
	assert(schema.findEntity("User").getProperty(2).propertyName == "flags");
	assert(schema.findEntity("User").findProperty("id").generated == true);
	assert(schema.findEntity("User").findProperty("id").key == true);
    assert(schema.findEntity("User").findProperty("name").key == false);
    assert(schema.findEntity("Customer").findProperty("id").generated == true);
	assert(schema.findEntity("Customer").findProperty("id").key == true);

	assert(schema.findEntity("User").findProperty("id").readFunc !is null);

    auto e2 = schema.createEntity("User");
    assert(e2 !is null);
    User e2user = cast(User)e2;
    assert(e2user !is null);

    e2user.customerId = 25;
    Variant v = schema.getPropertyValue(e2user, "customerId");
    assert(v == 25);
    e2user.customerId.nullify;
    assert(schema.getPropertyValue(e2user, "customerId") is Variant(null));
    schema.setPropertyValue(e2user, "customerId", Variant(42));
    assert(e2user.customerId == 42);
    assert(schema.getPropertyValue(e2user, "customerId") == 42);

	Object e1 = schema.findEntity("User").createEntity();
	assert(e1 !is null);
	User e1user = cast(User)e1;
	assert(e1user !is null);
	e1user.id = 25;



}

unittest {
    if (MYSQL_TESTS_ENABLED) {
        recreateTestSchema();
        
        // Checking generated metadata
        EntityMetaData schema = new SchemaInfoImpl!(User, Customer, T1);
        Dialect dialect = new MySQLDialect();
        DataSource ds = createUnitTestMySQLDataSource();
        SessionFactory factory = new SessionFactoryImpl(schema, dialect, ds);
        Session sess = factory.openSession();
        scope(exit) sess.close();

        User u1 = cast(User)sess.load("User", Variant(1));
        //writeln("Loaded value: " ~ u1.toString);
        assert(u1.id == 1);
        assert(u1.name == "user 1");

        User u2 = cast(User)sess.load("User", Variant(2));
        assert(u2.name == "user 2");
        assert(u2.flags == 22); // NULL is loaded as 0 if property cannot hold nulls

        User u3 = cast(User)sess.get("User", Variant(3));
        assert(u3.name == "user 3");
        assert(u3.flags == 0); // NULL is loaded as 0 if property cannot hold nulls
        assert(u3.getComment() !is null);

        User u4 = new User();
        sess.load(u4, Variant(4));
        assert(u4.name == "user 4");
        assert(u4.getComment() is null);

        User u5 = new User();
        u5.id = 5;
        sess.refresh(u5);
        assert(u5.name == "test user 5");
        assert(!u5.customerId.isNull);

        User u6 = cast(User)sess.load("User", Variant(6));
		assert(u6.name == "test user 6");
        assert(u6.customerId.isNull);

		// check Session.save() when id is filled
		Customer c4 = new Customer();
		c4.id = 4;
		c4.name = "Customer_4";
		sess.save(c4);

		Customer c4_check = cast(Customer)sess.load("Customer", Variant(4));
		assert(c4.id == c4_check.id);
		assert(c4.name == c4_check.name);

		sess.remove(c4);

		c4 = cast(Customer)sess.get("Customer", Variant(4));
		assert (c4 is null);

		Customer c5 = new Customer();
		c5.name = "Customer_5";
		sess.save(c5);

		assertThrown!HibernatedException(sess.createQuery("SELECT id, name, blabla FROM User ORDER BY name"));
		assertThrown!SyntaxError(sess.createQuery("SELECT id: name FROM User ORDER BY name"));

		// test multiple row query
		Query q = sess.createQuery("FROM User ORDER BY name");
		User[] list = cast(User[])q.list();
		assert(list.length == 6);
		assert(list[0].name == "test user 5");
		assert(list[1].name == "test user 6");
		assert(list[2].name == "user 1");
//		writeln("Read " ~ to!string(list.length) ~ " rows from User");
//		foreach(row; list) {
//			writeln(row.toString());
//		}
		Variant[][] rows = q.listRows();
		assert(rows.length == 6);
		//		foreach(row; rows) {
//			writeln(row);
//		}
		assertThrown!HibernatedException(q.uniqueResult());
		assertThrown!HibernatedException(q.uniqueRow());

		// test single row select
		q = sess.createQuery("FROM User AS u WHERE id = :Id and (u.name like '%test%' or flags=44)");
		assertThrown!HibernatedException(q.list()); // cannot execute w/o all parameters set
		q.setParameter("Id", Variant(6));
		list = cast(User[])q.list();
		assert(list.length == 1);
		assert(list[0].name == "test user 6");
//		writeln("Read " ~ to!string(list.length) ~ " rows from User");
//		foreach(row; list) {
//			writeln(row.toString());
//		}
		User uu = cast(User)q.uniqueResult();
		assert(uu.name == "test user 6");
		Variant[] row = q.uniqueRow();
		assert(row[0] == 6L);
		assert(row[1] == "test user 6");

		// test empty SELECT result
		q.setParameter("Id", Variant(7));
		row = q.uniqueRow();
		assert(row is null);
		uu = cast(User)q.uniqueResult();
		assert(uu is null);
	}
}


