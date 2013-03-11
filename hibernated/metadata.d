module hibernated.metadata;

import std.stdio;
import std.traits;
import std.typecons;
import std.string;
import hibernated.annotations;
import hibernated.type;

interface ClassMetadata {
	immutable string getEntityName();
	immutable TypeInfo getMappedClass();
	immutable string[] getPropertyNames();
}

class PropertyInfo {
public:
	immutable string fieldName;
	immutable string columnName;
	immutable Type columnType;
	immutable int length;
	immutable bool key;
	immutable bool generated;
	immutable bool nullable;
	this(string fieldName, string columnName, immutable Type columnType, int length, bool key, bool generated, bool nullable) {
		this.fieldName = fieldName;
		this.columnName = columnName;
		this.columnType = columnType;
		this.length = length;
		this.key = key;
		this.generated = generated;
		this.nullable = nullable;
	}
}

class EntityInfo {
	immutable string name;
	immutable string tableName;
	immutable PropertyInfo[] properties;
	public this(immutable string name, immutable string tableName, immutable PropertyInfo[] properties) {
		this.name = name;
		this.tableName = tableName;
		this.properties = properties;
	}
}


bool isHibernatedAnnotation(alias t)() {
	return is(typeof(t) == Id) || is(typeof(t) == Entity) || is(typeof(t) == Column) || is(typeof(t) == Table);
}

bool isHibernatedEntityAnnotation(alias t)() {
	return is(typeof(t) == Entity);
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
	}
	return false;
}

bool hasGeneratedAnnotation(T, string m)() {
	foreach (a; __traits(getAttributes, __traits(getMember,T,m))) {
		static if (is(typeof(a) == Generated)) {
			return true;
		}
	}
	return false;
}

string getColumnName(T, string m)() {
	foreach (a; __traits(getAttributes, __traits(getMember,T,m))) {
		static if (is(typeof(a) == Column)) {
			return a.name;
		}
	}
	return null;
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

string getPropertyDef(T, immutable string m)() {
	immutable bool isId = hasIdAnnotation!(T, m)();
	immutable bool isGenerated = hasGeneratedAnnotation!(T, m)();
	immutable string name = getColumnName!(T, m)();
	immutable length = getColumnLength!(T, m)();
	immutable bool nullable = getColumnNullable!(T, m)();
	immutable bool unique = getColumnUnique!(T, m)();
	return "new PropertyInfo(\"" ~ name ~ "\"," ~ format("%s",length) ~ "," ~ (nullable ? "true" : "false") ~ ")";
}

string entityInfo(T)() {
	string res;
	string generatedGettersSetters;

	string generatedEntityInfo;
	string generatedPropertyInfo;

	immutable string typeName = T.stringof;

	static assert (hasHibernatedEntityAnnotation!T(), "Type " ~ typeName ~ " has no Entity annotation");

	immutable string entityName = getEntityName!T();
	immutable string tableName = getTableName!T();
	pragma(msg, "entityName=" ~ entityName);
	pragma(msg, "tableName=" ~ tableName);

	static assert (entityName != null, "Type " ~ typeName ~ " has no Entity name specified");
	static assert (tableName != null, "Type " ~ typeName ~ " has no Table name specified");

	generatedEntityInfo ~= "new EntityInfo(";
	generatedEntityInfo ~= "\"" ~ entityName ~ "\",";
	generatedEntityInfo ~= "\"" ~ tableName ~ "\",";
	generatedEntityInfo ~= "cast (immutable PropertyInfo[]) [\n";

	foreach (m; __traits(allMembers, T)) {
		//pragma(msg, m);

		static if (__traits(compiles, (typeof(__traits(getMember, T, m))))){
			
			static if (hasHibernatedAnnotation!(T, m)) {
				pragma(msg, "Member " ~ m ~ " has known annotation");
			}

			alias typeof(__traits(getMember, T, m)) ti;


			static if (__traits(getAttributes, __traits(getMember, T, m)).length >= 1) {
				
				immutable string propertyDef = getPropertyDef!(T, m)();
				pragma(msg, propertyDef);

				if (generatedPropertyInfo != null)
					generatedPropertyInfo ~= ",\n";
				generatedPropertyInfo ~= propertyDef;

				
				static if (is(ti == function)) {
					// 
					immutable string fieldName = getterNameToFieldName(m);
					
					pragma(msg, "Function Name to Field name:");
					pragma(msg, fieldName);
				} else {
					// field
					immutable string membername = m;
					immutable string getterName = "get" ~ capitalizeFieldName(m);
					immutable string setterName = "set" ~ capitalizeFieldName(m);
					
					pragma(msg, getterName);
					pragma(msg, setterName);
					generatedGettersSetters ~= "   public " ~ ti.stringof ~ " " ~ getterName ~ "() { return " ~ m ~ "; }\n";
					generatedGettersSetters ~= "   public void " ~ setterName ~ "(" ~ ti.stringof ~ " " ~ m ~ ") { this." ~ m ~ " = " ~ m ~ "; }\n";
				}
				
				
				
				if (res.length > 0)
					res ~= ", ";
				res ~= m;
				res ~= "(";
				
				pragma(msg, __traits(getAttributes, __traits(getMember, T, m)));
				
				foreach(a; __traits(getAttributes, __traits(getMember, T, m))) {
					
					static if (isHibernatedAnnotation!a) {
						pragma(msg, "Is known attribute");
					}
					
					pragma(msg, a);
					//pragma(msg, a.name);
					static if (is(typeof(a) == Column)) {
						pragma(msg, "Attribute is Column");
						pragma(msg, a.name);
						res ~= a.name;
					}
				}
				
				static if (is(ti == long)) {
					pragma(msg, "Member is long field");
				}
				static if (is(ti == function)) {
					pragma(msg, "Member is function");
				}
				static if (is(ti == Nullable!long)) {
					pragma(msg, "Member is Nullable!long");
				}
				//immutable TypeInfo * ti = typeof(__traits(getMember, T, m));
				pragma(msg, typeof(__traits(getMember, T, m)));
				res ~= ")";
			}
		}
	}
	//pragma(msg, t);
	//pragma(msg, typeof(t));

	generatedEntityInfo ~= generatedPropertyInfo;
	generatedEntityInfo ~= "])";

	return generatedEntityInfo ~ "\n" ~ generatedGettersSetters;
}



class MetadataInfo(T) {
	string name;
	static string fields = GenerateFieldList!(T);
}

unittest {

	EntityInfo entity = new EntityInfo("user", "users", cast (immutable PropertyInfo[]) [
	                                                     new PropertyInfo("id", "id", new IntegerType(), 0, true, true, false)
	                                                     ]);



	//assert(entity.properties.length == 0);
	writeln("Running unittests");

	@Entity("User1")
	@Table("users")
	class User {

		@Id @Generated
		@Column("id")
		int id;

		@Column("name")
		string name;
		
		//mixin GenerateEntityMetadata!();
		//pragma(msg, "User entity fields: " ~ fields);
	}

	immutable string info = entityInfo!User();

	pragma(msg, info);

	writeln("User entity info: " ~ info);

	pragma(msg, "Hello from unittest");
	//assert(false);
	assert(true);
}
