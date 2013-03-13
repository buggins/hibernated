module hibernated.metadata;

import std.conv;
import std.stdio;
import std.string;
import std.traits;
import std.typecons;
import std.typetuple;

import ddbc.core;

import hibernated.annotations;
import hibernated.type;

//interface ClassMetadata {
//	immutable string getEntityName();
//	immutable TypeInfo getMappedClass();
//	immutable string[] getPropertyNames();
//}



class PropertyInfo {
public:
	alias void function(Object, DataSetReader, int index) ReaderFunc;
	alias void function(Object, DataSetWriter, int index) WriterFunc;
	immutable string propertyName;
	immutable string columnName;
	immutable Type columnType;
	immutable int length;
	immutable bool key;
	immutable bool generated;
	immutable bool nullable;
	ReaderFunc readFunc;
	WriterFunc writeFunc;
	this(string propertyName, string columnName, immutable Type columnType, int length, bool key, bool generated, bool nullable, ReaderFunc reader, WriterFunc writer) {
		this.propertyName = propertyName;
		this.columnName = columnName;
		this.columnType = columnType;
		this.length = length;
		this.key = key;
		this.generated = generated;
		this.nullable = nullable;
		this.readFunc = reader;
		this.writeFunc = writer;
	}
}

class EntityInfo {
	immutable string name;
	immutable string tableName;
	immutable PropertyInfo [] properties;
	immutable PropertyInfo [string] propertyMap;
	immutable (TypeInfo_Class) classInfo;
	public this(immutable string name, immutable string tableName, immutable PropertyInfo [] properties, immutable (TypeInfo_Class) classInfo) {
		this.name = name;
		this.tableName = tableName;
		this.properties = properties;
		this.classInfo = classInfo;
		immutable (PropertyInfo) [string] map;
		foreach(p; properties)
			map[p.propertyName] = p;
		this.propertyMap = cast(immutable PropertyInfo [string]) map;
	}
	immutable (PropertyInfo[]) getProperties() immutable { return properties; }
	immutable (PropertyInfo[string]) getPropertyMap() immutable { return propertyMap; }
	ulong getPropertyCount() immutable { return properties.length; }
	immutable (PropertyInfo) getProperty(int propertyIndex) immutable { return properties[propertyIndex]; }
	immutable (PropertyInfo) findProperty(string propertyName) immutable { return propertyMap[propertyName]; }
	Object createEntity() immutable { return Object.factory((cast(TypeInfo_Class)classInfo).name); }
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

string getPropertyReadCode(T, string m)() {
	alias typeof(__traits(getMember, T, m)) ti;
	static if (is(ti == function)) {
		return "entity." ~ m ~ "()";
	}
	return "entity." ~ m;
}

string getPropertyWriteCode(T, string m)() {
	alias typeof(__traits(getMember, T, m)) ti;
	static if (is(ti == function)) {
		return "entity." ~ getterNameToSetterName(m) ~ "(" ~ getColumnTypeDatasetReadCode!(T, m)() ~ ");";
	}
	return "entity." ~ m ~ " = " ~ getColumnTypeDatasetReadCode!(T, m)() ~ ";";
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

//	pragma(msg, propertyReadCode);
//	pragma(msg, datasetReadCode);
//	pragma(msg, propertyWriteCode);
//	pragma(msg, datasetWriteCode);
	pragma(msg, readerFuncDef);
	pragma(msg, writerFuncDef);

	static assert (typeName != null, "Cannot determine column type for member " ~ m ~ " of type " ~ T.stringof);
	return "    new PropertyInfo(\"" ~ propertyName ~ "\", \"" ~ columnName ~ "\", " ~ typeName ~ ", " ~ 
			format("%s",length) ~ ", " ~ (isId ? "true" : "false")  ~ ", " ~ 
			(isGenerated ? "true" : "false")  ~ ", " ~ (nullable ? "true" : "false") ~ ", " ~ 
			readerFuncDef ~ ", " ~
			writerFuncDef ~ ", " ~
			")";
}

string getEntityDef(T)() {
	string res;
	string generatedGettersSetters;

	string generatedEntityInfo;
	string generatedPropertyInfo;

	immutable string typeName = T.stringof;

	static assert (hasHibernatedEntityAnnotation!T(), "Type " ~ typeName ~ " has no Entity annotation");

	immutable string entityName = getEntityName!T();
	immutable string tableName = getTableName!T();

	static assert (entityName != null, "Type " ~ typeName ~ " has no Entity name specified");
	static assert (tableName != null, "Type " ~ typeName ~ " has no Table name specified");

	generatedEntityInfo ~= "new EntityInfo(";
	generatedEntityInfo ~= "\"" ~ entityName ~ "\", ";
	generatedEntityInfo ~= "\"" ~ tableName ~ "\", ";
	generatedEntityInfo ~= "cast (immutable PropertyInfo []) [\n";

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
	generatedEntityInfo ~= "cast(immutable TypeInfo_Class)" ~ typeName ~ ".classinfo";
	generatedEntityInfo ~= ")";

	return generatedEntityInfo ~ "\n" ~ generatedGettersSetters;
}


string entityListDef(T ...)() {
	string res;
	foreach(t; T) {
		immutable string def = getEntityDef!t;
		if (res.length > 0)
			res ~= ",\n";
		res ~= def;
	}
	return 
		"static this() {\n" ~
		"    entities = cast(immutable EntityInfo [])[\n" ~ res ~ "];\n" ~
		"    immutable (EntityInfo) [string] map;\n" ~
		"    immutable (EntityInfo) [TypeInfo_Class] typemap;\n" ~
		"    foreach(e; entities) {\n" ~
		"        map[e.name] = e;\n" ~
		"        writeln((cast(TypeInfo_Class)e.classInfo).toString());\n" ~
		"        typemap[cast(TypeInfo_Class)e.classInfo] = e;\n" ~
		"    }\n" ~
		"    entityMap = cast(immutable EntityInfo [string])map;\n" ~
		"    classMap = cast(immutable EntityInfo [TypeInfo_Class])map;\n" ~
		"}";
}

abstract class SchemaInfo {
	public immutable (EntityInfo []) getEntities() immutable;
	public immutable (EntityInfo [string]) getEntityMap() immutable;
	public immutable (EntityInfo [TypeInfo_Class]) getClassMap() immutable;
	public immutable (EntityInfo) findEntity(string entityName) immutable;
	public immutable (EntityInfo) getEntity(int entityIndex) immutable;
	public int getEntityCount() immutable;
	public immutable (EntityInfo) findEntityByClass(Object obj) immutable {
		writeln("search for " ~ obj.classinfo.name);
		return getEntityMap()[obj.classinfo.name];
//		if ((obj.classinfo in getClassMap()) is null)
//			throw new Exception("Class " ~ obj.classinfo.toString() ~ " not found in map of size " ~ to!string(getClassMap().length));
//		immutable (EntityInfo) ei = getClassMap()[obj.classinfo];
//		return ei;
	}
	public void readAllColumns(Object obj, DataSetReader r, int startColumn) immutable {
		writeln("ClassInfo = " ~ obj.classinfo.toString());
		immutable EntityInfo ei = findEntityByClass(obj);
//		for (int i = 0; i<ei.getPropertyCount(); i++) {
//			ei.getProperty(i).readFunc(obj, r, startColumn + i);
//		}
	}
}

class SchemaInfoImpl(T...) : SchemaInfo {
	static immutable EntityInfo [string] entityMap;
	static immutable EntityInfo [] entities;
	static immutable (EntityInfo [TypeInfo_Class]) classMap;
	mixin(entityListDef!(T)());

	override public immutable (EntityInfo[]) getEntities()  immutable { return entities; }
	override public immutable (EntityInfo[string]) getEntityMap()  immutable { return entityMap; }
	override public immutable (EntityInfo) findEntity(string entityName)  immutable { return entityMap[entityName]; }
	override public immutable (EntityInfo) getEntity(int entityIndex)  immutable { return entities[entityIndex]; }
	override public immutable (EntityInfo [TypeInfo_Class]) getClassMap()  immutable { return classMap; }
	override public int getEntityCount()  immutable { return cast(int)entities.length; }
}

//class MetadataInfo(T) {
//	string name;
//	static string fields = GenerateFieldList!(T);
//}

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


unittest {

	EntityInfo entity = new EntityInfo("user", "users", cast (immutable PropertyInfo []) [
	                                                     new PropertyInfo("id", "id", new IntegerType(), 0, true, true, false, null, null)
	                                                     ], null);

	assert(entity.properties.length == 1);


//	immutable string info = getEntityDef!User();
//	immutable string infos = entityListDef!(User, Customer)();

	immutable EntityInfo ei = cast(immutable EntityInfo)new EntityInfo("User", "users", cast (immutable PropertyInfo []) [
	                                                                 new PropertyInfo("id", "id_column", new IntegerType(), 0, true, true, false, null, null),
                                                                      new PropertyInfo("name", "name_column", new StringType(), 0, false, false, false, null, null),
                                                                      new PropertyInfo("flags", "flags", new StringType(), 0, false, false, true, null, null),
                                                                      new PropertyInfo("login", "login", new StringType(), 0, false, false, true, null, null),
                                                                      new PropertyInfo("testColumn", "testcolumn", new IntegerType(), 0, false, false, true, null, null)], null);

	void function(User, DataSetReader, int) readFunc = function(User entity, DataSetReader reader, int index) { };

	assert(ei.findProperty("name").columnName == "name_column");
	assert(ei.getProperties()[0].columnName == "id_column");
	assert(ei.getProperty(2).propertyName == "flags");
	assert(ei.getPropertyCount == 5);

	EntityInfo[] entities3 =  [
	                                                                 new EntityInfo("User", "users", cast (immutable PropertyInfo []) [
	                                                                 new PropertyInfo("id", "id_column", new IntegerType(), 0, true, true, false, null, null),
	                                                                  new PropertyInfo("name", "name_column", new StringType(), 0, false, false, false, null, null),
	                                                                  new PropertyInfo("flags", "flags", new StringType(), 0, false, false, true, null, null),
	                                                                  new PropertyInfo("login", "login", new StringType(), 0, false, false, true, null, null),
	                                                                  new PropertyInfo("testColumn", "testcolumn", new IntegerType(), 0, false, false, true, null, null)], null)
	                                                                 ,
	                                                                 new EntityInfo("Customer", "customer", cast (immutable PropertyInfo []) [
                                                                     new PropertyInfo("id", "id", new IntegerType(), 0, false, false, true, null, null),
                                                                     new PropertyInfo("name", "name", new StringType(), 0, false, false, true, null, null)], null)
	                                                                 ];


	// Checking generated metadata
	immutable SchemaInfo schema = cast(immutable SchemaInfo) new SchemaInfoImpl!(User, Customer);
	assert(schema.getEntityCount() == 2);
	assert(schema.findEntity("User").findProperty("name").columnName == "name_column");
	assert(schema.findEntity("User").getProperties()[0].columnName == "id_column");
	assert(schema.findEntity("User").getProperty(2).propertyName == "flags");
	assert(schema.findEntity("User").findProperty("id").generated == true);
	assert(schema.findEntity("User").findProperty("id").key == true);
	assert(schema.findEntity("Customer").findProperty("id").generated == true);
	assert(schema.findEntity("Customer").findProperty("id").key == true);

	assert(schema.findEntity("User").findProperty("id").readFunc !is null);

	Object e1 = schema.findEntity("User").createEntity();
	assert(e1 !is null);
	User e1user = cast(User)e1;
	assert(e1user !is null);
	e1user.id = 25;
}
