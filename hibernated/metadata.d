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

import hibernated.annotations;
import hibernated.core;
import hibernated.type;

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
	/// returns property by index
	PropertyInfo getProperty(int propertyIndex) { return properties[propertyIndex]; }
	/// returns property by name, throws exception if not found
	PropertyInfo findProperty(string propertyName) { return propertyMap[propertyName]; }
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
	PROPERTY_MEMBER, // @property int field() { return _field; }
}

PropertyMemberKind getPropertyMemberKind(T, string m)() {
	alias typeof(__traits(getMember, T, m)) ti;
	static if (is(ti == function)) {
		static if (functionAttributes!ti & FA.property)
			return PROPERTY_MEMBER;
		else
			return GETTER_MEMBER;
	}
	return FIELD_MEMBER;
}

enum PropertyMemberType : int {
	INT_TYPE,
	LONG_TYPE,
	STRING_TYPE,
	GETTER_INT_TYPE,
	GETTER_LONG_TYPE,
	GETTER_STRING_TYPE,
}

string getPropertyReadCode(T, string m)() {
	alias typeof(__traits(getMember, T, m)) ti;
	static if (is(ti == function)) {
		return "entity." ~ m ~ "()";
	}
	return "entity." ~ m;
}

string getColumnTypeKeyIsSetCode(T, string m)() {
	alias typeof(__traits(getMember, T, m)) ti;
	static if (is(ti == int)) {
		return "(entity." ~ m ~ " != 0)";
	}
	static if (is(ti == long)) {
		return "(entity." ~ m ~ " != 0)";
	}
	static if (is(ti == string)) {
		return "(entity." ~ m ~ " !is null)";
	}
	static if (is(ti == function)) {
		immutable getter = "(entity." ~ m ~ "()";
		static if (is(ReturnType!(ti) == int)) {
			return getter ~ " != 0)";
		}
		static if (is(ReturnType!(ti) == long)) {
			return getter ~ " != 0)";
		}
		static if (is(ReturnType!(ti) == string)) {
			return getter ~ " !is null)";
		}
	}
	return null;
}

string getColumnTypeIsNullCode(T, string m)() {
	alias typeof(__traits(getMember, T, m)) ti;
	static if (is(ti == int)) {
		return "false";
	}
	static if (is(ti == long)) {
		return "false";
	}
	static if (is(ti == string)) {
		return "(entity." ~ m ~ " is null)";
	}
	static if (is(ti == function)) {
		immutable getter = "(entity." ~ m ~ "()";
		static if (is(ReturnType!(ti) == int)) {
			return "false";
		}
		static if (is(ReturnType!(ti) == long)) {
			return "false";
		}
		static if (is(ReturnType!(ti) == string)) {
			return getter ~ " is null)";
		}
	}
	return null;
}


string getPropertyWriteCode(T, string m)() {
	alias typeof(__traits(getMember, T, m)) ti;
	static if (is(ti == function)) {
		return "entity." ~ getterNameToSetterName(m) ~ "(" ~ getColumnTypeDatasetReadCode!(T, m)() ~ ");";
	}
	return "entity." ~ m ~ " = " ~ getColumnTypeDatasetReadCode!(T, m)() ~ ";";
}

string getPropertyVariantWriteCode(T, string m)() {
	alias typeof(__traits(getMember, T, m)) ti;
	static if (is(ti == function)) {
		return "entity." ~ getterNameToSetterName(m) ~ "(" ~ getColumnTypeVariantReadCode!(T, m)() ~ ");";
	}
	return "entity." ~ m ~ " = " ~ getColumnTypeVariantReadCode!(T, m)() ~ ";";
}

string getColumnTypeName(T, string m)() {
	alias typeof(__traits(getMember, T, m)) ti;
	static if (is(ti == int)) {
		return "new IntegerType()";
	}
	static if (is(ti == long)) {
		return "new BigIntegerType()";
	}
	static if (is(ti == string)) {
		return "new StringType()";
	}
	static if (is(ti == function)) {
		static if (is(ReturnType!(ti) == int)) {
			return "new IntegerType()";
		}
		static if (is(ReturnType!(ti) == long)) {
			return "new IntegerType()";
		}
		static if (is(ReturnType!(ti) == string)) {
			return "new StringType()";
		}
	}
	return null;
}

string getColumnTypeDatasetReadCode(T, string m)() {
	alias typeof(__traits(getMember, T, m)) ti;
	static if (is(ti == int)) {
		return "r.getInt(index)";
	}
	static if (is(ti == long)) {
		return "r.getLong(index)";
	}
	static if (is(ti == string)) {
		return "r.getString(index)";
	}
	static if (is(ti == function)) {
		static if (is(ReturnType!(ti) == int)) {
			return "r.getInt(index)";
		}
		static if (is(ReturnType!(ti) == long)) {
			return "r.getLong(index)";
		}
		static if (is(ReturnType!(ti) == string)) {
			return "r.getString(index)";
		}
	}
	return null;
}

string getColumnTypeVariantReadCode(T, string m)() {
	alias typeof(__traits(getMember, T, m)) ti;
	static if (is(ti == int)) {
		return "(value == null ? 0 : value.get!(int))";
	}
	static if (is(ti == long)) {
		return "(value == null ? 0 : value.get!(long))";
	}
	static if (is(ti == string)) {
		return "(value == null ? null : value.get!(string))";
	}
	static if (is(ti == function)) {
		static if (is(ReturnType!(ti) == int)) {
			return "(value == null ? 0 : value.get!(int))";
		}
		static if (is(ReturnType!(ti) == long)) {
			return "(value == null ? 0 : value.get!(long))";
		}
		static if (is(ReturnType!(ti) == string)) {
			return "(value == null ? null : value.get!(string))";
		}
	}
	return null;
}

string getColumnTypeDatasetWriteCode(T, string m)() {
	alias typeof(__traits(getMember, T, m)) ti;
	immutable string readCode = getPropertyReadCode!(T,m)();
	static if (is(ti == int)) {
		return "r.setInt(index, " ~ readCode ~ ");";
	}
	static if (is(ti == long)) {
		return "r.setLong(index, " ~ readCode ~ ");";
	}
	static if (is(ti == string)) {
		return "r.setString(index, " ~ readCode ~ ");";
	}
	static if (is(ti == function)) {
		static if (is(ReturnType!(ti) == int)) {
			return "r.setInt(index, " ~ readCode ~ ");";
		}
		static if (is(ReturnType!(ti) == long)) {
			return "r.setLong(index, " ~ readCode ~ ");";
		}
		static if (is(ReturnType!(ti) == string)) {
			return "r.setString(index, " ~ readCode ~ ");";
		}
	}
	return null;
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
			"    Variant v; \n" ~
			"    v = " ~ propertyReadCode ~ "; \n" ~
			"    return v; \n" ~
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
    public string generateFindAllForEntity(string entityName);
    public string getAllFieldList(EntityInfo ei);
    public string getAllFieldList(string entityName);
    public string generateFindByPkForEntity(EntityInfo ei);
    public string generateFindByPkForEntity(string entityName);
}

abstract class SchemaInfo : EntityMetaData {

    public string getAllFieldList(EntityInfo ei) {
        string query;
        for (int i = 0; i < ei.getPropertyCount(); i++) {
            if (query.length != 0)
                query ~= ", ";
            query ~= ei.getProperty(i).columnName;
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

    public string generateFindAllForEntity(string entityName) {
		EntityInfo ei = findEntity(entityName);
        return "SELECT " ~ getAllFieldList(ei) ~ " FROM " ~ ei.tableName;
	}

    public string generateFindByPkForEntity(EntityInfo ei) {
        return "SELECT " ~ getAllFieldList(ei) ~ " FROM " ~ ei.tableName ~ " WHERE " ~ ei.keyProperty.columnName ~ " = ?";
    }

    public string generateFindByPkForEntity(string entityName) {
        return generateFindByPkForEntity(findEntity(entityName));
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
            throw new HibernatedException("Cannot find entity by name " ~ entityName, e);
        }
    }
    public EntityInfo findEntity(TypeInfo_Class entityClass) { 
        try {
            return classMap[entityClass]; 
        } catch (Exception e) {
            throw new HibernatedException("Cannot find entity by class " ~ entityClass.toString(), e);
        }
    }
    public EntityInfo getEntity(int entityIndex) { 
        try {
            return entities[entityIndex]; 
        } catch (Exception e) {
            throw new HibernatedException("Cannot get entity by index " ~ to!string(entityIndex), e);
        }
    }
    public Object createEntity(string entityName) { 
        try {
            return entityMap[entityName].createEntity(); 
        } catch (Exception e) {
            throw new HibernatedException("Cannot find entity by name " ~ entityName, e);
        }
    }
    public EntityInfo findEntityForObject(Object obj) {
        try {
            return classMap[obj.classinfo];
        } catch (Exception e) {
            throw new HibernatedException("Cannot find entity metadata for " ~ obj.classinfo.toString(), e);
        }
    }
}


unittest {

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
        @Column
        long flags;
        @Column
        string comment;
        override string toString() {
            return "id=" ~ to!string(id) ~ ", name=" ~ name ~ ", flags=" ~ to!string(flags) ~ ", comment=" ~ comment;
        }
    }
    
}


unittest {
	// Checking generated metadata
	EntityMetaData schema = new SchemaInfoImpl!(User, Customer);

	assert(schema.getEntityCount() == 2);
	assert(schema.findEntity("User").findProperty("name").columnName == "name_column");
	assert(schema.findEntity("User").getProperties()[0].columnName == "id_column");
	assert(schema.findEntity("User").getProperty(2).propertyName == "flags");
	assert(schema.findEntity("User").findProperty("id").generated == true);
	assert(schema.findEntity("User").findProperty("id").key == true);
	assert(schema.findEntity("Customer").findProperty("id").generated == true);
	assert(schema.findEntity("Customer").findProperty("id").key == true);

	assert(schema.findEntity("User").findProperty("id").readFunc !is null);

    auto e2 = schema.createEntity("User");
    assert(e2 !is null);
    User e2user = cast(User)e2;
    assert(e2user !is null);

	Object e1 = schema.findEntity("User").createEntity();
	assert(e1 !is null);
	User e1user = cast(User)e1;
	assert(e1user !is null);
	e1user.id = 25;
}

unittest {

}


