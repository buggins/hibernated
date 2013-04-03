/**
 * HibernateD - Object-Relation Mapping for D programming language, with interface similar to Hibernate. 
 * 
 * Hibernate documentation can be found here:
 * $(LINK http://hibernate.org/docs)$(BR)
 * 
 * Source file hibernated/metadata.d.
 *
 * This module contains implementation of Annotations parsing and ORM model metadata holder classes.
 * 
 * Copyright: Copyright 2013
 * License:   $(LINK www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Author:   Vadim Lopatin
 */
module hibernated.metadata;

import std.ascii;
import std.conv;
import std.datetime;
import std.exception;
import std.stdio;
import std.string;
import std.traits;
import std.typecons;
import std.typetuple;
import std.variant;
import std.uuid;

import ddbc.core;
import ddbc.common;

import hibernated.annotations;
import hibernated.core;
import hibernated.type;
import hibernated.session;
import hibernated.dialect;
import hibernated.dialects.mysqldialect;


abstract class EntityMetaData {

	@property size_t length();
	const(EntityInfo) opIndex(int index) const;
    const(EntityInfo) opIndex(string entityName) const;
    const(PropertyInfo) opIndex(string entityName, string propertyName) const;

    public string getEntityName(TypeInfo_Class type) const {
        return getClassMap()[type].name;
    }
    
    public string getEntityNameForClass(T)() const {
        return getClassMap()[T.classinfo].name;
    }

    int opApply(int delegate(ref const EntityInfo) dg) const;
    

    public const(EntityInfo[]) getEntities() const;
    public const(EntityInfo[string]) getEntityMap() const;
    public const(EntityInfo[TypeInfo_Class]) getClassMap() const;
    public const(EntityInfo) findEntity(string entityName) const;
    public const(EntityInfo) findEntity(TypeInfo_Class entityClass) const;
    public const(EntityInfo) findEntityForObject(Object obj) const;
    public const(EntityInfo) getEntity(int entityIndex) const;
	public int getEntityCount() const;
	/// Entity factory
	public Object createEntity(string entityName) const;
	/// Fills all properties of entity instance from dataset
    public int readAllColumns(Object obj, DataSetReader r, int startColumn) const;
	/// Puts all properties of entity instance to dataset
    public int writeAllColumns(Object obj, DataSetWriter w, int startColumn, bool exceptKey = false) const;

    public string generateFindAllForEntity(string entityName) const;

    public int getFieldCount(const EntityInfo ei, bool exceptKey) const;

    public string getAllFieldList(const EntityInfo ei, bool exceptKey = false) const;
    public string getAllFieldList(string entityName, bool exceptKey = false) const;

    public string generateFindByPkForEntity(const EntityInfo ei) const;
    public string generateFindByPkForEntity(string entityName) const;

    public string generateInsertAllFieldsForEntity(const EntityInfo ei) const;
    public string generateInsertAllFieldsForEntity(string entityName) const;
    public string generateInsertNoKeyForEntity(const EntityInfo ei) const;
    public string generateUpdateForEntity(const EntityInfo ei) const;

    public Variant getPropertyValue(Object obj, string propertyName) const;
    public void setPropertyValue(Object obj, string propertyName, Variant value) const;
}

enum RelationType {
	None,
	Embedded,
	OneToOne,
	OneToMany,
	ManyToOne,
	ManyToMany,
}

/// Metadata of entity property
class PropertyInfo {
public:
    /// reads simple property value from data set to object
	alias void function(Object, DataSetReader, int index) ReaderFunc;
    /// writes simple property value to data set from object
    alias void function(Object, DataSetWriter, int index) WriterFunc;
    /// copy property from second passed object to first
    alias void function(Object, Object) CopyFunc;
    /// returns simple property as Variant
    alias Variant function(Object) GetVariantFunc;
    /// sets simple property from Variant
    alias void function(Object, Variant value) SetVariantFunc;
    /// returns true if property value of object is not null
    alias bool function(Object) IsNullFunc;
    /// returns true if key property of object is set (similar to IsNullFunc but returns true if non-nullable number is 0.
    alias bool function(Object) KeyIsSetFunc;
    /// returns OneToOne, ManyToOne or Embedded property as Object
    alias Object function(Object) GetObjectFunc;
    /// sets OneToOne, ManyToOne or Embedded property as Object
    alias void function(Object, Object) SetObjectFunc;
    /// sets lazy loader delegate for OneToOne, or ManyToOne property if it's Lazy! template instance
    alias void function(Object, Object delegate()) SetObjectDelegateFunc;
    /// sets lazy loader delegate for OneToMany, or ManyToMany property if it's LazyCollection! template instance
    alias void function(Object, Object[] delegate()) SetCollectionDelegateFunc;
    /// returns OneToMany or ManyToMany property value as object array
    alias Object[] function(Object) GetCollectionFunc;
    /// sets OneToMany or ManyToMany property value from object array
    alias void function(Object, Object[]) SetCollectionFunc;
    /// returns true if Lazy! or LazyCollection! property is loaded (no loader delegate set).
    alias bool function(Object) IsLoadedFunc;
    /// returns new generated primary key for property
    alias Variant function(Connection conn, const PropertyInfo prop) GeneratorFunc;

    package EntityInfo _entity;
    @property const(EntityInfo) entity() const { return _entity; }
    @property const(EntityMetaData) metadata() const { return _entity._metadata; }

	immutable string propertyName;
    immutable string columnName;
    immutable Type columnType;
    immutable int length;
    immutable bool key;
    immutable bool generated;
    immutable bool nullable;
    immutable RelationType relation;
    immutable bool lazyLoad;
    immutable bool collection;

    immutable string referencedEntityName; // for @Embedded, @OneToOne, @OneToMany, @ManyToOne, @ManyToMany holds name of entity
	package EntityInfo _referencedEntity; // for @Embedded, @OneToOne, @OneToMany, @ManyToOne, @ManyToMany holds entity info reference, filled in runtime
    @property const(EntityInfo) referencedEntity() const { return _referencedEntity; }

    immutable string referencedPropertyName; // for @OneToOne, @OneToMany, @ManyToOne
	package PropertyInfo _referencedProperty;
    @property const(PropertyInfo) referencedProperty() const { return _referencedProperty; }

    package int _columnOffset; // offset from first column of this entity in selects
    @property int columnOffset() const { return _columnOffset; } // offset from first column of this entity in selects

    package JoinTableInfo _joinTable;
    @property const (JoinTableInfo) joinTable() const { return _joinTable; }

    immutable ReaderFunc readFunc;
    immutable WriterFunc writeFunc;
    immutable GetVariantFunc getFunc;
    immutable SetVariantFunc setFunc;
    immutable KeyIsSetFunc keyIsSetFunc;
    immutable IsNullFunc isNullFunc;
    immutable GetObjectFunc getObjectFunc;
    immutable SetObjectFunc setObjectFunc;
    immutable CopyFunc copyFieldFunc;
    immutable GetCollectionFunc getCollectionFunc;
    immutable SetCollectionFunc setCollectionFunc;
    immutable SetObjectDelegateFunc setObjectDelegateFunc;
    immutable SetCollectionDelegateFunc setCollectionDelegateFunc;
    immutable IsLoadedFunc isLoadedFunc;
    immutable GeneratorFunc generatorFunc;

    @property bool simple() const { return relation == RelationType.None; };
    @property bool embedded() const { return relation == RelationType.Embedded; };
    @property bool oneToOne() const { return relation == RelationType.OneToOne; };
    @property bool oneToMany() const { return relation == RelationType.OneToMany; };
    @property bool manyToOne() const { return relation == RelationType.ManyToOne; };
    @property bool manyToMany() const { return relation == RelationType.ManyToMany; };

    this(string propertyName, string columnName, Type columnType, int length, bool key, bool generated, bool nullable, RelationType relation, string referencedEntityName, string referencedPropertyName, ReaderFunc reader, WriterFunc writer, GetVariantFunc getFunc, SetVariantFunc setFunc, KeyIsSetFunc keyIsSetFunc, IsNullFunc isNullFunc, 
            CopyFunc copyFieldFunc, 
            GeneratorFunc generatorFunc = null,
            GetObjectFunc getObjectFunc = null, 
            SetObjectFunc setObjectFunc = null, 
            GetCollectionFunc getCollectionFunc = null, 
            SetCollectionFunc setCollectionFunc = null,
            SetObjectDelegateFunc setObjectDelegateFunc = null, 
            SetCollectionDelegateFunc setCollectionDelegateFunc = null, 
            IsLoadedFunc isLoadedFunc = null,
            bool lazyLoad = false, bool collection = false,
            JoinTableInfo joinTable = null) {
		this.propertyName = propertyName;
		this.columnName = columnName;
		this.columnType = cast(immutable Type)columnType;
		this.length = length;
		this.key = key;
		this.generated = generated;
		this.nullable = nullable;
		this.relation = relation;
		this.referencedEntityName =referencedEntityName;
		this.referencedPropertyName = referencedPropertyName;
		this.readFunc = reader;
		this.writeFunc = writer;
		this.getFunc = getFunc;
		this.setFunc = setFunc;
		this.keyIsSetFunc = keyIsSetFunc;
		this.isNullFunc = isNullFunc;
		this.getObjectFunc = getObjectFunc;
		this.setObjectFunc = setObjectFunc;
        this.copyFieldFunc = copyFieldFunc;
        this.generatorFunc = generatorFunc;
        this.lazyLoad = lazyLoad;
        this.collection = collection;
        this.setObjectDelegateFunc = setObjectDelegateFunc;
        this.setCollectionDelegateFunc = setCollectionDelegateFunc;
        this.getCollectionFunc = getCollectionFunc;
        this.setCollectionFunc = setCollectionFunc;
        this.isLoadedFunc = isLoadedFunc;
        this._joinTable = joinTable;
	}

    package void updateJoinTable() {
        assert(relation == RelationType.ManyToMany);
        assert(_joinTable !is null);
        _joinTable.setEntities(entity, referencedEntity);
    }

    const hash_t opHash() const {
        return (cast(hash_t)(cast(void*)this)) * 31;
    }

    const bool opEquals(ref const PropertyInfo s) const {
        return this == s;
    }

    const int opCmp(ref const PropertyInfo s) const {
        return this == s ? 0 : (opHash() > s.opHash() ? 1 : -1);
    }
}

/// Metadata of single entity
class EntityInfo {

    package EntityMetaData _metadata;
    @property const(EntityMetaData) metadata() const { return _metadata; }

    immutable string name;
    immutable string tableName;
    private PropertyInfo[] _properties;
    @property const(PropertyInfo[]) properties() const { return _properties; }
    package PropertyInfo [string] _propertyMap;
	immutable TypeInfo_Class classInfo;
    private int _keyIndex;
    @property int keyIndex() const { return _keyIndex; }
    private PropertyInfo _keyProperty;
    @property const(PropertyInfo) keyProperty() const { return _keyProperty; }

	immutable bool embeddable;


    int opApply(int delegate(ref const PropertyInfo) dg) const { 
        int result = 0; 
        for (int i = 0; i < _properties.length; i++) { 
            result = dg(_properties[i]); 
            if (result) break; 
        } 
        return result; 
    }

	public this(string name, string tableName, bool embeddable, PropertyInfo [] properties, TypeInfo_Class classInfo) {
		this.name = name;
		this.tableName = tableName;
		this.embeddable = embeddable;
		this._properties = properties;
		this.classInfo = cast(immutable TypeInfo_Class)classInfo;
		PropertyInfo[string] map;
		foreach(i, p; properties) {
            p._entity = this;
			map[p.propertyName] = p;
            if (p.key) {
                _keyIndex = cast(int)i;
                _keyProperty = p;
            }
        }
		this._propertyMap = map;
        enforceEx!HibernatedException(keyProperty !is null || embeddable, "No key specified for non-embeddable entity " ~ name);
	}
	/// returns key value as Variant from entity instance
    Variant getKey(Object obj) const { return keyProperty.getFunc(obj); }
    /// returns key value as Variant from data set
    Variant getKey(DataSetReader r, int startColumn) const { return r.getVariant(startColumn + keyProperty.columnOffset); }
    /// sets key value from Variant
    void setKey(Object obj, Variant value) const { keyProperty.setFunc(obj, value); }
    /// returns property info for key property
    const(PropertyInfo) getKeyProperty() const { return keyProperty; }
    /// checks if primary key is set (for non-nullable member types like int or long, 0 is considered as non-set)
    bool isKeySet(Object obj) const { return keyProperty.keyIsSetFunc(obj); }
    /// checks if primary key is set (for non-nullable member types like int or long, 0 is considered as non-set)
    bool isKeyNull(DataSetReader r, int startColumn) const { return r.isNull(startColumn + keyProperty.columnOffset); }
    /// checks if property value is null
    bool isNull(Object obj) const { return keyProperty.isNullFunc(obj); }
	/// returns property value as Variant
    Variant getPropertyValue(Object obj, string propertyName) const { return findProperty(propertyName).getFunc(obj); }
	/// sets property value from Variant
    void setPropertyValue(Object obj, string propertyName, Variant value) const { return findProperty(propertyName).setFunc(obj, value); }
	/// returns all properties as array
    const (PropertyInfo[]) getProperties() const { return properties; }
	/// returns map of property name to property metadata
    const (PropertyInfo[string]) getPropertyMap() const { return _propertyMap; }
	/// returns number of properties
    ulong getPropertyCount() const { return properties.length; }
	/// returns number of properties
    ulong getPropertyCountExceptKey() const { return properties.length - 1; }

    @property size_t length() const { return properties.length; }

	const(PropertyInfo) opIndex(int index) const {
		return properties[index];
	}

    const(PropertyInfo) opIndex(string propertyName) const {
		return findProperty(propertyName);
	}

	/// returns property by index
    const(PropertyInfo) getProperty(int propertyIndex) const { return properties[propertyIndex]; }
	/// returns property by name, throws exception if not found
	const(PropertyInfo) findProperty(string propertyName) const { try { return _propertyMap[propertyName]; } catch (Throwable e) { throw new HibernatedException("No property " ~ propertyName ~ " found in entity " ~ name); } }
	/// create instance of entity object (using default constructor)
	Object createEntity() const { return Object.factory(classInfo.name); }

    void copyAllProperties(Object to, Object from) const {
        foreach(pi; this)
            pi.copyFieldFunc(to, from);
    }
}

class JoinTableInfo {
    package string _tableName;
    @property string tableName() const { return _tableName; }
    package string _column1;
    @property string column1() const { return _column1; }
    package string _column2;
    @property string column2() const { return _column2; }
    package EntityInfo _thisEntity;
    @property const (EntityInfo) thisEntity() { return _thisEntity; }
    package EntityInfo _otherEntity;
    @property const (EntityInfo) otherEntity() { return _otherEntity; }
    this(string tableName, string column1, string column2) {
        this._tableName = tableName;
        this._column1 = column1;
        this._column2 = column2;
    }
    /// set entities, and replace missing parameters with default generated values
    package void setEntities(const EntityInfo thisEntity, const EntityInfo otherEntity) {
        assert(thisEntity !is null);
        assert(otherEntity !is null);
        this._thisEntity = cast(EntityInfo)thisEntity;
        this._otherEntity = cast(EntityInfo)otherEntity;
        // table name is constructed from names of two entities delimited with underscore, sorted in alphabetical order, with appended suffix 's': entity1_entity2s
        // (to get same table name on two sides)
        string entity1 = camelCaseToUnderscoreDelimited(thisEntity.name < otherEntity.name ? thisEntity.name : otherEntity.name);
        string entity2 = camelCaseToUnderscoreDelimited(thisEntity.name < otherEntity.name ? otherEntity.name : thisEntity.name);
        _tableName = _tableName !is null ? _tableName : entity1 ~ "_" ~ entity2 ~ "s";
        // columns are entity name (CamelCase to camel_case
        _column1 = _column1 !is null ? _column1 : camelCaseToUnderscoreDelimited(thisEntity.name) ~ "_fk";
        _column2 = _column2 !is null ? _column2 : camelCaseToUnderscoreDelimited(otherEntity.name) ~ "_fk";
    }
    static string generateJoinTableCode(string table, string column1, string column2) {
        return "new JoinTableInfo(" ~ quoteString(table) ~ ", " ~ quoteString(column1) ~ ", " ~ quoteString(column2) ~ ")";
    }
    
}

string quoteString(string s) {
    return s is null ? "null" : "\"" ~ s ~ "\"";
}

string quoteBool(bool b) {
    return b ? "true" : "false";
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

/// converts camel case MyEntityName to my_entity_name
string camelCaseToUnderscoreDelimited(immutable string s) {
	string res;
	bool lastLower = false;
	foreach(ch; s) {
		if (ch >= 'A' && ch <= 'Z') {
			if (lastLower) {
				lastLower = false;
				res ~= "_";
			}
			res ~= toLower(ch);
		} else if (ch >= 'a' && ch <= 'z') {
			lastLower = true;
			res ~= ch;
		} else {
			res ~= ch;
		}
	}
	return res;
}

unittest {
	static assert(camelCaseToUnderscoreDelimited("User") == "user");
	static assert(camelCaseToUnderscoreDelimited("MegaTableName") == "mega_table_name");
}

/// returns true if class member has at least one known property level annotation (@Column, @Id, @Generated)
bool hasHibernatedPropertyAnnotation(T, string m)() {
    return hasOneOfMemberAnnotations!(T, m, Id, Embedded, Column, OneToOne, ManyToOne, ManyToMany, OneToMany, Generated, Generator);
}

/// returns true if class has one of specified anotations
bool hasOneOfAnnotations(T : Object, A...)() {
    foreach(a; A) {
        static if (hasAnnotation!(T, a)) {
            return true;
        }
    }
	return false;
}

/// returns true if class member has one of specified anotations
bool hasOneOfMemberAnnotations(T : Object, string m, A...)() {
    foreach(a; A) {
        static if (hasMemberAnnotation!(T, m, a)) {
            return true;
        }
    }
	return false;
}

/// returns true if class has specified anotations
bool hasAnnotation(T, A)() {
	foreach(a; __traits(getAttributes, T)) {
		static if (is(typeof(a) == A) || a.stringof == A.stringof) {
			return true;
		}
	}
	return false;
}

/// returns true if class member has specified anotations
bool hasMemberAnnotation(T, string m, A)() {
	foreach(a; __traits(getAttributes, __traits(getMember,T,m))) {
		static if (is(typeof(a) == A) || a.stringof == A.stringof) {
			return true;
		}
	}
	return false;
}

/// returns entity name for class type
string getEntityName(T : Object)() {
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

/// returns table name for class type
string getTableName(T : Object)() {
	foreach (a; __traits(getAttributes, T)) {
		static if (is(typeof(a) == Table)) {
			return a.name;
		}
	}
	return camelCaseToUnderscoreDelimited(T.stringof);
}

string applyDefault(string s, string defaultValue) {
	return s != null && s.length > 0 ? s : defaultValue;
}

string getColumnName(T, string m)() {
	foreach (a; __traits(getAttributes, __traits(getMember,T,m))) {
		static if (is(typeof(a) == Column)) {
			return applyDefault(a.name, camelCaseToUnderscoreDelimited(getPropertyName!(T,m)()));
		}
		static if (a.stringof == Column.stringof) {
			return camelCaseToUnderscoreDelimited(getPropertyName!(T,m)());
		}
	}
	return camelCaseToUnderscoreDelimited(m);
}

string getGeneratorCode(T, string m)() {
    foreach (a; __traits(getAttributes, __traits(getMember,T,m))) {
        static if (is(typeof(a) == Generator)) {
            static assert(a.code != null && a.code != "", "@Generator doesn't have code specified");
            return a.code;
        }
        static if (a.stringof == Generator.stringof) {
            static assert(false, "@Generator doesn't have code specified");
        }
    }
    return null;
}

string getJoinColumnName(T, string m)() {
	foreach (a; __traits(getAttributes, __traits(getMember,T,m))) {
		static if (is(typeof(a) == JoinColumn)) {
			return applyDefault(a.name, camelCaseToUnderscoreDelimited(getPropertyName!(T,m)()) ~ "_fk");
		}
		static if (a.stringof == JoinColumn.stringof) {
			return camelCaseToUnderscoreDelimited(getPropertyName!(T,m)()) ~ "_fk";
		}
	}
	return null;
}

string getJoinTableName(T, string m)() {
    foreach (a; __traits(getAttributes, __traits(getMember,T,m))) {
        static if (is(typeof(a) == JoinTable)) {
            return emptyStringToNull(a.joinTableName);
        }
    }
    return null;
}

string getJoinTableColumn1(T, string m)() {
    foreach (a; __traits(getAttributes, __traits(getMember,T,m))) {
        static if (is(typeof(a) == JoinTable)) {
            return emptyStringToNull(a.joinColumn1);
        }
    }
    return null;
}

string getJoinTableColumn2(T, string m)() {
    foreach (a; __traits(getAttributes, __traits(getMember,T,m))) {
        static if (is(typeof(a) == JoinTable)) {
            return emptyStringToNull(a.joinColumn2);
        }
    }
    return null;
}

string emptyStringToNull(string s) {
	return (s is null || s.length == 0) ? null : s;
}

string getOneToOneReferencedPropertyName(T, string m)() {
	foreach (a; __traits(getAttributes, __traits(getMember,T,m))) {
		static if (is(typeof(a) == OneToOne)) {
			return emptyStringToNull(a.name);
		}
		static if (a.stringof == OneToOne.stringof) {
			return null;
		}
	}
	return null;
}

string getOneToManyReferencedPropertyName(T, string m)() {
    foreach (a; __traits(getAttributes, __traits(getMember,T,m))) {
        static if (is(typeof(a) == OneToMany)) {
            return emptyStringToNull(a.name);
        }
        static if (a.stringof == OneToOne.stringof) {
            return null;
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
    LAZY_MEMBER,     // Lazy!Object field;
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

static immutable string[] PropertyMemberKind_ReadCode = 
    [
    	"entity.%s",
        "entity.%s()",
     	"entity.%s",
        "entity.%s()",
    ];

PropertyMemberKind getPropertyMemberKind(T : Object, string m)() {
	alias typeof(__traits(getMember, T, m)) ti;
	static if (is(ti == function)) {
		static if (functionAttributes!ti & FunctionAttribute.property)
			return PropertyMemberKind.PROPERTY_MEMBER;
		else
			return PropertyMemberKind.GETTER_MEMBER;
	} else {
        static if (isLazyInstance!(ti)) {
            return PropertyMemberKind.LAZY_MEMBER;
        } else {
		    return PropertyMemberKind.FIELD_MEMBER;
        }
	}
}

string getPropertyEmbeddedEntityName(T : Object, string m)() {
	alias typeof(__traits(getMember, T, m)) ti;
	static if (is(ti == function)) {
		static if (isImplicitlyConvertible!(ReturnType!(ti), Object)) {
			static assert(hasAnnotation!(ReturnType!(ti), Embeddable), "@Embedded property class should have @Embeddable annotation");
			return getEntityName!(ReturnType!(ti));
		} else
			static assert(false, "@Embedded property can be only class with @Embeddable annotation");
	} else {
		static if (isImplicitlyConvertible!(ti, Object)) {
			static assert(hasAnnotation!(ti, Embeddable), "@Embedded property class should have @Embeddable annotation");
			return getEntityName!ti;
		} else 
			static assert(false, "@Embedded property can be only class with @Embeddable annotation");
	}
}

template isLazyInstance(T) {
    static if (is(T x == Lazy!Args, Args...))
        enum bool isLazyInstance = true;
    else
        enum bool isLazyInstance = false;
}

template isLazyCollectionInstance(T) {
    static if (is(T x == LazyCollection!Args, Args...))
        enum bool isLazyCollectionInstance = true;
    else
        enum bool isLazyCollectionInstance = false;
}

template isLazyMember(T : Object, string m) {
    static if (is(typeof(__traits(getMember, T, m)) x == Lazy!Args, Args...))
        enum bool isLazyMember = true;
    else
        enum bool isLazyMember = false;
}

template isLazyCollectionMember(T : Object, string m) {
    static if (is(typeof(__traits(getMember, T, m)) x == LazyCollection!Args, Args...))
        enum bool isLazyCollectionMember = true;
    else
        enum bool isLazyCollectionMember = false;
}

template isCollectionMember(T : Object, string m) {
    alias typeof(__traits(getMember, T, m)) ti;
    static if (is(typeof(__traits(getMember, T, m)) x == LazyCollection!Args, Args...))
        enum bool isCollectionMember = true;
    else {
        //pragma(msg, typeof(__traits(getMember, T, m).init[0]));
        static if (isArray!(ti) && isImplicitlyConvertible!(typeof(__traits(getMember, T, m).init[0]), Object))
            enum bool isCollectionMember = true;
        else
            enum bool isCollectionMember = false;
    }
}

template getLazyInstanceType(T) {
    static if (is(T x == Lazy!Args, Args...))
        alias Args[0] getLazyInstanceType;
    else {
        static assert(false, "Not a Lazy! instance");
    }
}

template getLazyCollectionInstanceType(T) {
    static if (is(T x == LazyCollection!Args, Args...))
        alias Args[0] getLazyInstanceType;
    else {
        static assert(false, "Not a LazyCollection! instance");
    }
}

template getReferencedInstanceType(T) {
    //pragma(msg, T.stringof);
    static if (is(T == delegate)) {
        //pragma(msg, "is delegate");
        static if (isImplicitlyConvertible!(ReturnType!(T), Object)) {
            alias ReturnType!(T) getReferencedInstanceType;
        } else
            static assert(false, "@OneToOne, @ManyToOne, @OneToMany, @ManyToMany property can be only class or Lazy!class");
    } else static if (is(T == function)) {
        //pragma(msg, "is function");
        static if (isImplicitlyConvertible!(ReturnType!(T), Object)) {
            alias ReturnType!(T) getReferencedInstanceType;
        } else {
            static if (is(ReturnType!(T) x == Lazy!Args, Args...))
                alias Args[0] getReferencedInstanceType;
            else
                static assert(false, "Type cannot be used as relation " ~ T.stringof);
        }
    } else {
        //pragma(msg, "is not function");
        static if (is(T x == LazyCollection!Args, Args...)) {
            alias Args[0] getReferencedInstanceType;
        } else {
            static if (is(T x == Lazy!Args, Args...)) {
                alias Args[0] getReferencedInstanceType;
            } else {
                static if (isArray!(T)) {
                    static if (isImplicitlyConvertible!(typeof(T.init[0]), Object)) {
                        //pragma(msg, "isImplicitlyConvertible!(T, Object)");
                        alias typeof(T.init[0]) getReferencedInstanceType;
                    } else {
                        static assert(false, "Type cannot be used as relation " ~ T.stringof);
                    }
                } else static if (isImplicitlyConvertible!(T, Object)) {
                    //pragma(msg, "isImplicitlyConvertible!(T, Object)");
                    alias T getReferencedInstanceType;
                } else static if (isImplicitlyConvertible!(T, Object[])) {
                    //pragma(msg, "isImplicitlyConvertible!(T, Object)");
                    alias T getReferencedInstanceType;
                } else {
                    static assert(false, "Type cannot be used as relation " ~ T.stringof);
                }
            }
        }
    }
}

string getPropertyReferencedEntityName(T : Object, string m)() {
	alias typeof(__traits(getMember, T, m)) ti;
    return getEntityName!(getReferencedInstanceType!ti);
}

string getPropertyEmbeddedClassName(T : Object, string m)() {
	alias typeof(__traits(getMember, T, m)) ti;
	static if (is(ti == function)) {
		static if (isImplicitlyConvertible!(ReturnType!(ti), Object)) {
			static assert(hasAnnotation!(ReturnType!(ti), Embeddable), "@Embedded property class should have @Embeddable annotation");
			return fullyQualifiedName!(ReturnType!(ti));
		} else
			static assert(false, "@Embedded property can be only class with @Embeddable annotation");
	} else {
		static if (isImplicitlyConvertible!(ti, Object)) {
			static assert(hasAnnotation!(ti, Embeddable), "@Embedded property class should have @Embeddable annotation");
			return fullyQualifiedName!ti;
		} else 
			static assert(false, "@Embedded property can be only class with @Embeddable annotation");
	}
}

string getPropertyReferencedClassName(T : Object, string m)() {
	alias typeof(__traits(getMember, T, m)) ti;
    return fullyQualifiedName!(getReferencedInstanceType!ti);
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
	FLOAT_TYPE,   // float
	DOUBLE_TYPE,   // double
	NULLABLE_FLOAT_TYPE, // Nullable!float
	NULLABLE_DOUBLE_TYPE,// Nullable!double
	STRING_TYPE,   // string
	DATETIME_TYPE, // std.datetime.DateTime
	DATE_TYPE, // std.datetime.Date
	TIME_TYPE, // std.datetime.TimeOfDay
	NULLABLE_DATETIME_TYPE, // Nullable!std.datetime.DateTime
	NULLABLE_DATE_TYPE, // Nullable!std.datetime.Date
	NULLABLE_TIME_TYPE, // Nullable!std.datetime.TimeOfDay
	BYTE_ARRAY_TYPE, // byte[]
	UBYTE_ARRAY_TYPE, // ubyte[]
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
		} else if (is(ReturnType!(ti) == float)) {
			return PropertyMemberType.FLOAT_TYPE;
		} else if (is(ReturnType!(ti) == double)) {
			return PropertyMemberType.DOUBLE_TYPE;
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
		} else if (is(ReturnType!(ti) == Nullable!float)) {
			return PropertyMemberType.NULLABLE_FLOAT_TYPE;
		} else if (is(ReturnType!(ti) == Nullable!double)) {
			return PropertyMemberType.NULLABLE_DOUBLE_TYPE;
		} else if (is(ReturnType!(ti) == string)) {
			return PropertyMemberType.STRING_TYPE;
		} else if (is(ReturnType!(ti) == DateTime)) {
			return PropertyMemberType.DATETIME_TYPE;
		} else if (is(ReturnType!(ti) == Date)) {
			return PropertyMemberType.DATE_TYPE;
		} else if (is(ReturnType!(ti) == TimeOfDay)) {
			return PropertyMemberType.TIME_TYPE;
		} else if (is(ReturnType!(ti) == Nullable!DateTime)) {
			return PropertyMemberType.NULLABLE_DATETIME_TYPE;
		} else if (is(ReturnType!(ti) == Nullable!Date)) {
			return PropertyMemberType.NULLABLE_DATE_TYPE;
		} else if (is(ReturnType!(ti) == Nullable!TimeOfDay)) {
			return PropertyMemberType.NULLABLE_TIME_TYPE;
		} else if (is(ReturnType!(ti) == byte[])) {
			return PropertyMemberType.BYTE_ARRAY_TYPE;
		} else if (is(ReturnType!(ti) == ubyte[])) {
			return PropertyMemberType.UBYTE_ARRAY_TYPE;
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
	} else if (is(ti == float)) {
		return PropertyMemberType.FLOAT_TYPE;
	} else if (is(ti == double)) {
		return PropertyMemberType.DOUBLE_TYPE;
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
	} else if (is(ti == Nullable!float)) {
		return PropertyMemberType.NULLABLE_FLOAT_TYPE;
	} else if (is(ti == Nullable!double)) {
		return PropertyMemberType.NULLABLE_DOUBLE_TYPE;
	} else if (is(ti == string)) {
		return PropertyMemberType.STRING_TYPE;
	} else if (is(ti == DateTime)) {
		return PropertyMemberType.DATETIME_TYPE;
	} else if (is(ti == Date)) {
		return PropertyMemberType.DATE_TYPE;
	} else if (is(ti == TimeOfDay)) {
		return PropertyMemberType.TIME_TYPE;
	} else if (is(ti == Nullable!DateTime)) {
		return PropertyMemberType.NULLABLE_DATETIME_TYPE;
	} else if (is(ti == Nullable!Date)) {
		return PropertyMemberType.NULLABLE_DATE_TYPE;
	} else if (is(ti == Nullable!TimeOfDay)) {
		return PropertyMemberType.NULLABLE_TIME_TYPE;
	} else if (is(ti == byte[])) {
		return PropertyMemberType.BYTE_ARRAY_TYPE;
	} else if (is(ti == ubyte[])) {
		return PropertyMemberType.UBYTE_ARRAY_TYPE;
	} else {
		assert (false, "Member " ~ m ~ " of class " ~ T.stringof ~ " has unsupported type " ~ ti.stringof);
	}
	//static assert (false, "Member " ~ m ~ " of class " ~ T.stringof ~ " has unsupported type " ~ ti.stringof);
}


string getPropertyReadCode(T, string m)() {
	return substituteParam(PropertyMemberKind_ReadCode[getPropertyMemberKind!(T,m)()], m);
}

static immutable bool[] ColumnTypeCanHoldNulls = 
	[
	 false, //BYTE_TYPE,    // byte
	 false, //SHORT_TYPE,   // short
	 false, //INT_TYPE,     // int
	 false, //LONG_TYPE,    // long
	 false, //UBYTE_TYPE,   // ubyte
	 false, //USHORT_TYPE,  // ushort
	 false, //UINT_TYPE,    // uint
	 false, //ULONG_TYPE,   // ulong
	 true, //NULLABLE_BYTE_TYPE,  // Nullable!byte
	 true, //NULLABLE_SHORT_TYPE, // Nullable!short
	 true, //NULLABLE_INT_TYPE,   // Nullable!int
	 true, //NULLABLE_LONG_TYPE,  // Nullable!long
	 true, //NULLABLE_UBYTE_TYPE, // Nullable!ubyte
	 true, //NULLABLE_USHORT_TYPE,// Nullable!ushort
	 true, //NULLABLE_UINT_TYPE,  // Nullable!uint
	 true, //NULLABLE_ULONG_TYPE, // Nullable!ulong
	 false,//FLOAT_TYPE,   // float
	 false,//DOUBLE_TYPE,   // double
	 true, //NULLABLE_FLOAT_TYPE, // Nullable!float
	 true, //NULLABLE_DOUBLE_TYPE,// Nullable!double
	 true, //STRING_TYPE   // string
	 false, //DATETIME_TYPE, // std.datetime.DateTime
	 false, //DATE_TYPE, // std.datetime.Date
	 false, //TIME_TYPE, // std.datetime.TimeOfDay
	 true, //NULLABLE_DATETIME_TYPE, // Nullable!std.datetime.DateTime
	 true, //NULLABLE_DATE_TYPE, // Nullable!std.datetime.Date
	 true, //NULLABLE_TIME_TYPE, // Nullable!std.datetime.TimeOfDay
	 true, //BYTE_ARRAY_TYPE, // byte[]
	 true, //UBYTE_ARRAY_TYPE, // ubyte[]
	 ];

string canColumnTypeHoldNulls(T, string m)() {
	return ColumnTypeCanHoldNulls[getPropertyMemberType!(T,m)];
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
	 "(%s != 0)",//FLOAT_TYPE,   // float
	 "(%s != 0)",//DOUBLE_TYPE,   // double
	 "(!%s.isNull)", //NULLABLE_FLOAT_TYPE, // Nullable!float
	 "(!%s.isNull)", //NULLABLE_DOUBLE_TYPE,// Nullable!double
	 "(%s !is null)", //STRING_TYPE   // string
	 "(%s != DateTime())", //DATETIME_TYPE, // std.datetime.DateTime
	 "(%s != Date())", //DATE_TYPE, // std.datetime.Date
	 "(%s != TimeOfDay())", //TIME_TYPE, // std.datetime.TimeOfDay
	 "(!%s.isNull)", //NULLABLE_DATETIME_TYPE, // Nullable!std.datetime.DateTime
	 "(!%s.isNull)", //NULLABLE_DATE_TYPE, // Nullable!std.datetime.Date
	 "(!%s.isNull)", //NULLABLE_TIME_TYPE, // Nullable!std.datetime.TimeOfDay
	 "(%s !is null)", //BYTE_ARRAY_TYPE, // byte[]
	 "(%s !is null)", //UBYTE_ARRAY_TYPE, // ubyte[]
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
	 "(false)",//FLOAT_TYPE,   // float
	 "(false)",//DOUBLE_TYPE,   // double
	 "(%s.isNull)", //NULLABLE_FLOAT_TYPE, // Nullable!float
	 "(%s.isNull)", //NULLABLE_DOUBLE_TYPE,// Nullable!double
	 "(%s is null)", //STRING_TYPE   // string
	 "(false)", //DATETIME_TYPE, // std.datetime.DateTime
	 "(false)", //DATE_TYPE, // std.datetime.Date
	 "(false)", //TIME_TYPE, // std.datetime.TimeOfDay
	 "(%s.isNull)", //NULLABLE_DATETIME_TYPE, // Nullable!std.datetime.DateTime
	 "(%s.isNull)", //NULLABLE_DATE_TYPE, // Nullable!std.datetime.Date
	 "(%s.isNull)", //NULLABLE_TIME_TYPE, // Nullable!std.datetime.TimeOfDay
	 "(%s is null)", //BYTE_ARRAY_TYPE, // byte[]
	 "(%s is null)", //UBYTE_ARRAY_TYPE, // ubyte[]
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
	 "float nv = 0;",//FLOAT_TYPE,   // float
	 "double nv = 0;",//DOUBLE_TYPE,   // double
	 "Nullable!float nv;", //NULLABLE_FLOAT_TYPE, // Nullable!float
	 "Nullable!double nv;", //NULLABLE_DOUBLE_TYPE,// Nullable!double
	 "string nv = null;", //STRING_TYPE   // string
	 "DateTime nv;", //DATETIME_TYPE, // std.datetime.DateTime
	 "Date nv;", //DATE_TYPE, // std.datetime.Date
	 "TimeOfDay nv;", //TIME_TYPE, // std.datetime.TimeOfDay
	 "Nullable!DateTime nv;", //NULLABLE_DATETIME_TYPE, // Nullable!std.datetime.DateTime
	 "Nullable!Date nv;", //NULLABLE_DATE_TYPE, // Nullable!std.datetime.Date
	 "Nullable!TimeOfDay nv;", //NULLABLE_TIME_TYPE, // Nullable!std.datetime.TimeOfDay
	 "byte[] nv = null;", //BYTE_ARRAY_TYPE, // byte[]
	 "ubyte[] nv = null;", //UBYTE_ARRAY_TYPE, // ubyte[]
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
	 "Variant(%s)",//FLOAT_TYPE,   // float
	 "Variant(%s)",//DOUBLE_TYPE,   // double
	 "(%s.isNull ? Variant(null) : Variant(%s.get()))", //NULLABLE_FLOAT_TYPE, // Nullable!float
	 "(%s.isNull ? Variant(null) : Variant(%s.get()))", //NULLABLE_DOUBLE_TYPE,// Nullable!double
	 "Variant(%s)", //STRING_TYPE   // string
	 "Variant(%s)", //DATETIME_TYPE, // std.datetime.DateTime
	 "Variant(%s)", //DATE_TYPE, // std.datetime.Date
	 "Variant(%s)", //TIME_TYPE, // std.datetime.TimeOfDay
	 "(%s.isNull ? Variant(null) : Variant(%s.get()))", //NULLABLE_DATETIME_TYPE, // Nullable!std.datetime.DateTime
	 "(%s.isNull ? Variant(null) : Variant(%s.get()))", //NULLABLE_DATE_TYPE, // Nullable!std.datetime.Date
	 "(%s.isNull ? Variant(null) : Variant(%s.get()))", //NULLABLE_TIME_TYPE, // Nullable!std.datetime.TimeOfDay
	 "Variant(%s)", //BYTE_ARRAY_TYPE, // byte[]
	 "Variant(%s)", //UBYTE_ARRAY_TYPE, // ubyte[]
	 ];

string getPropertyWriteCode(T, string m)() {
	immutable PropertyMemberKind kind = getPropertyMemberKind!(T, m)();
	immutable string nullValueCode = ColumnTypeSetNullCode[getPropertyMemberType!(T,m)()];
	immutable string datasetReader = "(!r.isNull(index) ? " ~ getColumnTypeDatasetReadCode!(T, m)() ~ " : nv)";
	final switch (kind) {
        case PropertyMemberKind.FIELD_MEMBER:
    		return nullValueCode ~ "entity." ~ m ~ " = " ~ datasetReader ~ ";";
        case PropertyMemberKind.LAZY_MEMBER:
            return nullValueCode ~ "entity." ~ m ~ " = " ~ datasetReader ~ ";";
        case PropertyMemberKind.GETTER_MEMBER:
    		return nullValueCode ~ "entity." ~ getterNameToSetterName(m) ~ "(" ~ datasetReader ~ ");";
        case PropertyMemberKind.PROPERTY_MEMBER:
	        return nullValueCode ~ "entity." ~ m ~ " = " ~ datasetReader ~ ";";
    }
}

string getPropertyCopyCode(T, string m)() {
    immutable PropertyMemberKind kind = getPropertyMemberKind!(T, m)();
    final switch (kind) {
        case PropertyMemberKind.FIELD_MEMBER:
            return "toentity." ~ m ~ " = fromentity." ~ m ~ ";";
        case PropertyMemberKind.LAZY_MEMBER:
            return "toentity." ~ m ~ " = fromentity." ~ m ~ "();";
        case PropertyMemberKind.GETTER_MEMBER:
            return "toentity." ~ getterNameToSetterName(m) ~ "(fromentity." ~ m ~ "());";
        case PropertyMemberKind.PROPERTY_MEMBER:
            return "toentity." ~ m ~ " = fromentity." ~ m ~ ";";
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
	 "new NumberType(2, false, SqlType.TINYINT)", //BYTE_TYPE,    // byte
	 "new NumberType(4, false, SqlType.SMALLINT)", //SHORT_TYPE,   // short
	 "new NumberType(9, false, SqlType.INTEGER)", //INT_TYPE,     // int
	 "new NumberType(20, false, SqlType.BIGINT)", //LONG_TYPE,    // long
	 "new NumberType(2, true, SqlType.TINYINT)", //UBYTE_TYPE,   // ubyte
	 "new NumberType(4, true, SqlType.SMALLINT)", //USHORT_TYPE,  // ushort
	 "new NumberType(9, true, SqlType.INTEGER)", //UINT_TYPE,    // uint
	 "new NumberType(20, true, SqlType.BIGINT)", //ULONG_TYPE,   // ulong
	 "new NumberType(2, false, SqlType.TINYINT)", //NULLABLE_BYTE_TYPE,  // Nullable!byte
	 "new NumberType(4, false, SqlType.SMALLINT)", //NULLABLE_SHORT_TYPE, // Nullable!short
	 "new NumberType(9, false, SqlType.INTEGER)", //NULLABLE_INT_TYPE,   // Nullable!int
	 "new NumberType(20, false, SqlType.BIGINT)", //NULLABLE_LONG_TYPE,  // Nullable!long
	 "new NumberType(2, true, SqlType.TINYINT)", //NULLABLE_UBYTE_TYPE, // Nullable!ubyte
	 "new NumberType(4, true, SqlType.SMALLINT)", //NULLABLE_USHORT_TYPE,// Nullable!ushort
	 "new NumberType(9, true, SqlType.INTEGER)", //NULLABLE_UINT_TYPE,  // Nullable!uint
	 "new NumberType(20, true, SqlType.BIGINT)", //NULLABLE_ULONG_TYPE, // Nullable!ulong
	 "new NumberType(7, false, SqlType.FLOAT)",//FLOAT_TYPE,   // float
	 "new NumberType(14, false, SqlType.DOUBLE)",//DOUBLE_TYPE,   // double
	 "new NumberType(7, false, SqlType.FLOAT)", //NULLABLE_FLOAT_TYPE, // Nullable!float
	 "new NumberType(14, false, SqlType.DOUBLE)", //NULLABLE_DOUBLE_TYPE,// Nullable!double
	 "new StringType()", //STRING_TYPE   // string
	 "new DateTimeType()", //DATETIME_TYPE, // std.datetime.DateTime
	 "new DateType()", //DATE_TYPE, // std.datetime.Date
	 "new TimeType()", //TIME_TYPE, // std.datetime.TimeOfDay
	 "new DateTimeType()", //NULLABLE_DATETIME_TYPE, // Nullable!std.datetime.DateTime
	 "new DateType()", //NULLABLE_DATE_TYPE, // Nullable!std.datetime.Date
	 "new TimeType()", //NULLABLE_TIME_TYPE, // Nullable!std.datetime.TimeOfDay
	 "new ByteArrayBlobType()", //BYTE_ARRAY_TYPE, // byte[]
	 "new UbyteArrayBlobType()", //UBYTE_ARRAY_TYPE, // ubyte[]
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
	 "r.getFloat(index)",//FLOAT_TYPE,   // float
	 "r.getDouble(index)",//DOUBLE_TYPE,   // double
	 "Nullable!float(r.getFloat(index))", //NULLABLE_FLOAT_TYPE, // Nullable!float
	 "Nullable!double(r.getDouble(index))", //NULLABLE_DOUBLE_TYPE,// Nullable!double
	 "r.getString(index)", //STRING_TYPE   // string
	 "r.getDateTime(index)", //DATETIME_TYPE, // std.datetime.DateTime
	 "r.getDate(index)", //DATE_TYPE, // std.datetime.Date
	 "r.getTime(index)", //TIME_TYPE, // std.datetime.TimeOfDay
	 "Nullable!DateTime(r.getDateTime(index))", //NULLABLE_DATETIME_TYPE, // Nullable!std.datetime.DateTime
	 "Nullable!Date(r.getDate(index))", //NULLABLE_DATE_TYPE, // Nullable!std.datetime.Date
	 "Nullable!TimeOfDay(r.getTime(index))", //NULLABLE_TIME_TYPE, // Nullable!std.datetime.TimeOfDay
	 "r.getBytes(index)", //BYTE_ARRAY_TYPE, // byte[]
	 "r.getUbytes(index)", //UBYTE_ARRAY_TYPE, // ubyte[]
	 ];

string getColumnTypeDatasetReadCode(T, string m)() {
	return ColumnTypeDatasetReaderCode[getPropertyMemberType!(T,m)()];
}

static immutable string[] ColumnTypeVariantReadCode = 
	[
	 "(value == null ? nv : (value.convertsTo!(byte) ? value.get!(byte) : (value.convertsTo!(long) ? to!byte(value.get!(long)) : to!byte((value.get!(ulong))))))", //BYTE_TYPE,    // byte
	 "(value == null ? nv : (value.convertsTo!(short) ? value.get!(short) : (value.convertsTo!(long) ? to!short(value.get!(long)) : to!short((value.get!(ulong))))))", //SHORT_TYPE,   // short
	 "(value == null ? nv : (value.convertsTo!(int) ? value.get!(int) : (value.convertsTo!(long) ? to!int(value.get!(long)) : to!int((value.get!(ulong))))))", //INT_TYPE,     // int
	 "(value == null ? nv : (value.convertsTo!(long) ? value.get!(long) : to!long(value.get!(ulong))))", //LONG_TYPE,    // long
	 "(value == null ? nv : (value.convertsTo!(ubyte) ? value.get!(ubyte) : (value.convertsTo!(ulong) ? to!ubyte(value.get!(ulong)) : to!ubyte((value.get!(long))))))", //UBYTE_TYPE,   // ubyte
	 "(value == null ? nv : (value.convertsTo!(ushort) ? value.get!(ushort) : (value.convertsTo!(ulong) ? to!ushort(value.get!(ulong)) : to!ushort((value.get!(long))))))", //USHORT_TYPE,  // ushort
	 "(value == null ? nv : (value.convertsTo!(uint) ? value.get!(uint) : (value.convertsTo!(ulong) ? to!uint(value.get!(ulong)) : to!uint((value.get!(long))))))", //UINT_TYPE,    // uint
	 "(value == null ? nv : (value.convertsTo!(ulong) ? value.get!(ulong) : to!ulong(value.get!(long))))", //ULONG_TYPE,   // ulong
	 "(value == null ? nv : (value.convertsTo!(byte) ? value.get!(byte) : (value.convertsTo!(long) ? to!byte(value.get!(long)) : to!byte((value.get!(ulong))))))", //NULLABLE_BYTE_TYPE,  // Nullable!byte
	 "(value == null ? nv : (value.convertsTo!(short) ? value.get!(short) : (value.convertsTo!(long) ? to!short(value.get!(long)) : to!short((value.get!(ulong))))))", //NULLABLE_SHORT_TYPE, // Nullable!short
	 "(value == null ? nv : (value.convertsTo!(int) ? value.get!(int) : (value.convertsTo!(long) ? to!int(value.get!(long)) : to!int((value.get!(ulong))))))", //NULLABLE_INT_TYPE,   // Nullable!int
	 "(value == null ? nv : (value.convertsTo!(long) ? value.get!(long) : to!long(value.get!(ulong))))", //NULLABLE_LONG_TYPE,  // Nullable!long
	 "(value == null ? nv : (value.convertsTo!(ubyte) ? value.get!(ubyte) : (value.convertsTo!(ulong) ? to!ubyte(value.get!(ulong)) : to!ubyte((value.get!(long))))))", //NULLABLE_UBYTE_TYPE, // Nullable!ubyte
	 "(value == null ? nv : (value.convertsTo!(ushort) ? value.get!(ushort) : (value.convertsTo!(ulong) ? to!ushort(value.get!(ulong)) : to!ushort((value.get!(long))))))", //NULLABLE_USHORT_TYPE,// Nullable!ushort
	 "(value == null ? nv : (value.convertsTo!(uint) ? value.get!(uint) : (value.convertsTo!(ulong) ? to!uint(value.get!(ulong)) : to!uint((value.get!(long))))))", //NULLABLE_UINT_TYPE,  // Nullable!uint
	 "(value == null ? nv : (value.convertsTo!(ulong) ? value.get!(ulong) : to!ulong(value.get!(long))))", //NULLABLE_ULONG_TYPE, // Nullable!ulong
	 "(value == null ? nv : (value.convertsTo!(float) ? value.get!(float) : to!float(value.get!(double))))",//FLOAT_TYPE,   // float
	 "(value == null ? nv : (value.convertsTo!(double) ? value.get!(double) : to!double(value.get!(double))))",//DOUBLE_TYPE,   // double
	 "(value == null ? nv : (value.convertsTo!(float) ? value.get!(float) : to!float(value.get!(double))))", //NULLABLE_FLOAT_TYPE, // Nullable!float
	 "(value == null ? nv : (value.convertsTo!(double) ? value.get!(double) : to!double(value.get!(double))))", //NULLABLE_DOUBLE_TYPE,// Nullable!double
	 "(value == null ? nv : value.get!(string))", //STRING_TYPE   // string
	 "(value == null ? nv : value.get!(DateTime))", //DATETIME_TYPE, // std.datetime.DateTime
	 "(value == null ? nv : value.get!(Date))", //DATE_TYPE, // std.datetime.Date
	 "(value == null ? nv : value.get!(TimeOfDay))", //TIME_TYPE, // std.datetime.TimeOfDay
	 "(value == null ? nv : value.get!(DateTime))", //NULLABLE_DATETIME_TYPE, // Nullable!std.datetime.DateTime
	 "(value == null ? nv : value.get!(Date))", //NULLABLE_DATE_TYPE, // Nullable!std.datetime.Date
	 "(value == null ? nv : value.get!(TimeOfDay))", //NULLABLE_TIME_TYPE, // Nullable!std.datetime.TimeOfDay
	 "(value == null ? nv : value.get!(byte[]))", //BYTE_ARRAY_TYPE, // byte[]
	 "(value == null ? nv : value.get!(ubyte[]))", //UBYTE_ARRAY_TYPE, // ubyte[]
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
	 "r.setFloat(index, %s);",//FLOAT_TYPE,   // float
	 "r.setDouble(index, %s);",//DOUBLE_TYPE,   // double
	 "r.setFloat(index, %s);", //NULLABLE_FLOAT_TYPE, // Nullable!float
	 "r.setDouble(index, %s);", //NULLABLE_DOUBLE_TYPE,// Nullable!double
	 "r.setString(index, %s);", //STRING_TYPE   // string
	 "r.setDateTime(index, %s);", //DATETIME_TYPE, // std.datetime.DateTime
	 "r.setDate(index, %s);", //DATE_TYPE, // std.datetime.Date
	 "r.setTime(index, %s);", //TIME_TYPE, // std.datetime.TimeOfDay
	 "r.setDateTime(index, %s);", //NULLABLE_DATETIME_TYPE, // Nullable!std.datetime.DateTime
	 "r.setDate(index, %s);", //NULLABLE_DATE_TYPE, // Nullable!std.datetime.Date
	 "r.setTime(index, %s);", //NULLABLE_TIME_TYPE, // Nullable!std.datetime.TimeOfDay
	 "r.setBytes(index, %s);", //BYTE_ARRAY_TYPE, // byte[]
	 "r.setUbytes(index, %s);", //UBYTE_ARRAY_TYPE, // ubyte[]
	 ];

string getColumnTypeDatasetWriteCode(T, string m)() {
	alias typeof(__traits(getMember, T, m)) ti;
	immutable string isNullCode = getColumnTypeIsNullCode!(T,m)();
	immutable string readCode = getPropertyReadCode!(T,m)();
	immutable string setDataCode = DatasetWriteCode[getPropertyMemberType!(T,m)()];
	return "if (" ~ isNullCode ~ ") r.setNull(index); else " ~ substituteParam(setDataCode, readCode);
}

string getEmbeddedPropertyVariantWriteCode(T, string m, string className)() {
	immutable PropertyMemberKind kind = getPropertyMemberKind!(T, m)();
	final switch (kind) {
        case PropertyMemberKind.FIELD_MEMBER:
		    return "entity." ~ m ~ " = (value == null ? null : value.get!(" ~ className ~ "));";
        case PropertyMemberKind.GETTER_MEMBER:
    		return "entity." ~ getterNameToSetterName(m) ~ "(value == null ? null : value.get!(" ~ className ~ "));";
        case PropertyMemberKind.LAZY_MEMBER:
            return "entity." ~ m ~ " = (value == null ? null : value.get!(" ~ className ~ "));";
        case PropertyMemberKind.PROPERTY_MEMBER:
       		return "entity." ~ m ~ " = (value == null ? null : value.get!(" ~ className ~ "));";
    }
}

string getCollectionPropertyVariantWriteCode(T, string m, string className)() {
    immutable PropertyMemberKind kind = getPropertyMemberKind!(T, m)();
    final switch (kind) {
        case PropertyMemberKind.FIELD_MEMBER:
            return "entity." ~ m ~ " = (value == null ? null : value.get!(" ~ className ~ "[]));";
        case PropertyMemberKind.GETTER_MEMBER:
            return "entity." ~ getterNameToSetterName(m) ~ "(value == null ? null : value.get!(" ~ className ~ "[]));";
        case PropertyMemberKind.LAZY_MEMBER:
            return "entity." ~ m ~ " = (value == null ? null : value.get!(" ~ className ~ "[]));";
        case PropertyMemberKind.PROPERTY_MEMBER:
            return "entity." ~ m ~ " = (value == null ? null : value.get!(" ~ className ~ "[]));";
    }
}

string getPropertyObjectWriteCode(T, string m, string className)() {
	immutable PropertyMemberKind kind = getPropertyMemberKind!(T, m)();
    final switch (kind) {
	    case PropertyMemberKind.FIELD_MEMBER:
		    return "entity." ~ m ~ " = cast(" ~ className ~ ")value;";
        case PropertyMemberKind.GETTER_MEMBER:
		    return "entity." ~ getterNameToSetterName(m) ~ "(cast(" ~ className ~ ")value);";
        case PropertyMemberKind.PROPERTY_MEMBER:
    		return "entity." ~ m ~ " = cast(" ~ className ~ ")value;";
        case PropertyMemberKind.LAZY_MEMBER:
            return "entity." ~ m ~ " = cast(" ~ className ~ ")value;";
    }
}

string getPropertyCollectionWriteCode(T, string m, string className)() {
    immutable PropertyMemberKind kind = getPropertyMemberKind!(T, m)();
    final switch (kind) {
        case PropertyMemberKind.FIELD_MEMBER:
            return "entity." ~ m ~ " = cast(" ~ className ~ "[])value;";
        case PropertyMemberKind.GETTER_MEMBER:
            return "entity." ~ getterNameToSetterName(m) ~ "(cast(" ~ className ~ "[])value);";
        case PropertyMemberKind.PROPERTY_MEMBER:
            return "entity." ~ m ~ " = cast(" ~ className ~ "[])value;";
        case PropertyMemberKind.LAZY_MEMBER:
            return "entity." ~ m ~ " = cast(" ~ className ~ "[])value;";
    }
}

string getLazyPropertyObjectWriteCode(T, string m)() {
    immutable PropertyMemberKind kind = getPropertyMemberKind!(T, m)();
    final switch (kind) {
        case PropertyMemberKind.FIELD_MEMBER:
            return "entity." ~ m ~ " = loader;";
        case PropertyMemberKind.GETTER_MEMBER:
            return "entity." ~ getterNameToSetterName(m) ~ "(loader);";
        case PropertyMemberKind.PROPERTY_MEMBER:
            return "entity." ~ m ~ " = loader;";
        case PropertyMemberKind.LAZY_MEMBER:
            return "entity." ~ m ~ " = loader;";
    }
}

string getLazyPropertyLoadedCode(T, string m)() {
    immutable PropertyMemberKind kind = getPropertyMemberKind!(T, m)();
    final switch (kind) {
        case PropertyMemberKind.FIELD_MEMBER:
            return "entity." ~ m ~ ".loaded";
        case PropertyMemberKind.GETTER_MEMBER:
            return "entity." ~ m ~ "().loaded";
        case PropertyMemberKind.PROPERTY_MEMBER:
            return "entity." ~ m ~ ".loaded";
        case PropertyMemberKind.LAZY_MEMBER:
            return "entity." ~ m ~ ".loaded";
    }
}


// TODO: minimize duplication of code in getXXXtoXXXPropertyDef

/// generate source code for creation of OneToOne definition
string getOneToOnePropertyDef(T, immutable string m)() {
    immutable string referencedEntityName = getPropertyReferencedEntityName!(T,m);
	immutable string referencedClassName = getPropertyReferencedClassName!(T,m);
	immutable string referencedPropertyName = getOneToOneReferencedPropertyName!(T,m);
	immutable string entityClassName = fullyQualifiedName!T;
    immutable string propertyName = getPropertyName!(T,m);
    static assert (propertyName != null, "Cannot determine property name for member " ~ m ~ " of type " ~ T.stringof);
    static assert (!hasOneOfMemberAnnotations!(T, m, Column, Id, Generated, Generator, ManyToOne, ManyToMany, Embedded), entityClassName ~ "." ~ propertyName ~ ": OneToOne property cannot have Column, Id, Generated, Generator, ManyToOne, ManyToMany or Embedded annotation");
    immutable bool isLazy = isLazyMember!(T,m);
    immutable string columnName = getJoinColumnName!(T, m);
	immutable length = getColumnLength!(T, m)();
	immutable bool hasNull = hasMemberAnnotation!(T,m, Null);
	immutable bool hasNotNull = hasMemberAnnotation!(T,m, NotNull);
	immutable bool nullable = hasNull ? true : (hasNotNull ? false : true); //canColumnTypeHoldNulls!(T.m)
	immutable bool unique = hasMemberAnnotation!(T, m, UniqueKey);
	immutable string typeName = "new EntityType(cast(immutable TypeInfo_Class)" ~ entityClassName ~ ".classinfo, \"" ~ entityClassName ~ "\")"; //getColumnTypeName!(T, m)();
	immutable string propertyReadCode = getPropertyReadCode!(T,m);
	immutable string datasetReadCode = null; //getColumnTypeDatasetReadCode!(T,m)();
	immutable string propertyWriteCode = null; //getPropertyWriteCode!(T,m)();
	immutable string datasetWriteCode = null; //getColumnTypeDatasetWriteCode!(T,m)();
	immutable string propertyVariantSetCode = getEmbeddedPropertyVariantWriteCode!(T, m, referencedClassName); // getPropertyVariantWriteCode!(T,m)();
	immutable string propertyVariantGetCode = "Variant(" ~ propertyReadCode ~ " is null ? null : " ~ propertyReadCode ~ ")"; //getPropertyVariantReadCode!(T,m)();
	immutable string propertyObjectSetCode = getPropertyObjectWriteCode!(T,m, referencedClassName); // getPropertyVariantWriteCode!(T,m)();
	immutable string propertyObjectGetCode = propertyReadCode; //getPropertyVariantReadCode!(T,m)();
	immutable string keyIsSetCode = null; //getColumnTypeKeyIsSetCode!(T,m)();
	immutable string isNullCode = propertyReadCode ~ " is null";
    immutable string copyFieldCode = getPropertyCopyCode!(T,m);
	//	pragma(msg, "property read: " ~ propertyReadCode);
	//	pragma(msg, "property write: " ~ propertyWriteCode);
	//	pragma(msg, "variant get: " ~ propertyVariantGetCode);
	immutable string readerFuncDef = "null";
	immutable string writerFuncDef = "null";
	immutable string getVariantFuncDef = 
		"\n" ~
			"function(Object obj) { \n" ~ 
			"    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
			"    return " ~ propertyVariantGetCode ~ "; \n" ~
			" }\n";
	immutable string setVariantFuncDef = 
		"\n" ~
			"function(Object obj, Variant value) { \n" ~ 
			"    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
			"    " ~ propertyVariantSetCode ~ "\n" ~
			" }\n";
	immutable string keyIsSetFuncDef = "\n" ~
		"function(Object obj) { \n" ~ 
			"    return false;\n" ~
			" }\n";
	immutable string isNullFuncDef = "\n" ~
		"function(Object obj) { \n" ~ 
			"    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
			"    return " ~ isNullCode ~ ";\n" ~
			" }\n";
	immutable string getObjectFuncDef = 
		"\n" ~
			"function(Object obj) { \n" ~ 
			"    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
			"    assert(entity !is null);\n" ~
			"    return " ~ propertyObjectGetCode ~ "; \n" ~
			" }\n";
	immutable string setObjectFuncDef = 
		"\n" ~
			"function(Object obj, Object value) { \n" ~ 
			"    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
			"    " ~ propertyObjectSetCode ~ "\n" ~
			" }\n";
    immutable string copyFuncDef = 
        "\n" ~
            "function(Object to, Object from) { \n" ~ 
            "    " ~ entityClassName ~ " toentity = cast(" ~ entityClassName ~ ")to; \n" ~
            "    " ~ entityClassName ~ " fromentity = cast(" ~ entityClassName ~ ")from; \n" ~
            "    " ~ copyFieldCode ~ "\n" ~
            " }\n";
    immutable string getCollectionFuncDef = "null";
    immutable string setCollectionFuncDef = "null";
    immutable string setObjectDelegateFuncDef = !isLazy ? "null" :
            "\n" ~
            "function(Object obj, Object delegate() loader) { \n" ~ 
            "    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
            "    " ~ getLazyPropertyObjectWriteCode!(T,m) ~ "\n" ~
            " }\n";
    immutable string setCollectionDelegateFuncDef = "null";
    immutable string isLoadedFuncDef = !isLazy ? "null" : 
            "\n" ~
            "function(Object obj) { \n" ~ 
            "    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
            "    return " ~ getLazyPropertyLoadedCode!(T,m) ~ ";\n" ~
            " }\n";
	
    return "    new PropertyInfo(" ~
            quoteString(propertyName) ~ ", " ~ 
            quoteString(columnName) ~ ", " ~ 
            typeName ~ ", " ~ 
		    format("%s",length) ~ ", " ~ 
            "false, " ~ // id
		    "false, " ~ // generated
            quoteBool(nullable) ~ ", " ~ 
		    "RelationType.OneToOne, " ~
            quoteString(referencedEntityName)  ~ ", " ~ 
            quoteString(referencedPropertyName)  ~ ", " ~ 
		    readerFuncDef ~ ", " ~
		    writerFuncDef ~ ", " ~
		    getVariantFuncDef ~ ", " ~
		    setVariantFuncDef ~ ", " ~
		    keyIsSetFuncDef ~ ", " ~
		    isNullFuncDef ~ ", " ~
            copyFuncDef ~ ", " ~
            "null, " ~ // generatorFunc
            getObjectFuncDef ~ ", " ~
            setObjectFuncDef ~ ", " ~
            getCollectionFuncDef ~ ", " ~
            setCollectionFuncDef ~ ", " ~
            setObjectDelegateFuncDef ~ ", " ~
            setCollectionDelegateFuncDef ~ ", " ~
            isLoadedFuncDef ~ ", " ~
            quoteBool(isLazy) ~ ", " ~ // lazy
            "false" ~ // collection
            ")";
}

/// generate source code for creation of ManyToOne definition
string getManyToOnePropertyDef(T, immutable string m)() {
    immutable string referencedEntityName = getPropertyReferencedEntityName!(T,m);
    immutable string referencedClassName = getPropertyReferencedClassName!(T,m);
    immutable string referencedPropertyName = getOneToOneReferencedPropertyName!(T,m);
    immutable string entityClassName = fullyQualifiedName!T;
    immutable string propertyName = getPropertyName!(T,m);
    static assert (propertyName != null, "Cannot determine property name for member " ~ m ~ " of type " ~ T.stringof);
    static assert (!hasOneOfMemberAnnotations!(T, m, Column, Id, Generated, Generator, OneToOne, ManyToMany, Embedded), entityClassName ~ "." ~ propertyName ~ ": ManyToOne property cannot have Column, Id, Generated, Generator, OneToOne, ManyToMany or Embedded annotation");
    immutable string columnName = getJoinColumnName!(T, m);
    static assert (columnName != null, "ManyToOne property " ~ m ~ " has no JoinColumn name");
    immutable bool isLazy = isLazyMember!(T,m);
    immutable length = getColumnLength!(T, m);
    immutable bool hasNull = hasMemberAnnotation!(T,m, Null);
    immutable bool hasNotNull = hasMemberAnnotation!(T,m, NotNull);
    immutable bool nullable = hasNull ? true : (hasNotNull ? false : true); //canColumnTypeHoldNulls!(T.m)
    immutable bool unique = hasMemberAnnotation!(T, m, UniqueKey);
    immutable string typeName = "new EntityType(cast(immutable TypeInfo_Class)" ~ entityClassName ~ ".classinfo, \"" ~ entityClassName ~ "\")"; //getColumnTypeName!(T, m)();
    immutable string propertyReadCode = getPropertyReadCode!(T,m)();
    immutable string datasetReadCode = null; //getColumnTypeDatasetReadCode!(T,m)();
    immutable string propertyWriteCode = null; //getPropertyWriteCode!(T,m)();
    immutable string datasetWriteCode = null; //getColumnTypeDatasetWriteCode!(T,m)();
    immutable string propertyVariantSetCode = getEmbeddedPropertyVariantWriteCode!(T, m, referencedClassName); // getPropertyVariantWriteCode!(T,m)();
    immutable string propertyVariantGetCode = "Variant(" ~ propertyReadCode ~ " is null ? null : " ~ propertyReadCode ~ ")"; //getPropertyVariantReadCode!(T,m)();
    immutable string propertyObjectSetCode = getPropertyObjectWriteCode!(T,m, referencedClassName); // getPropertyVariantWriteCode!(T,m)();
    immutable string propertyObjectGetCode = propertyReadCode; //getPropertyVariantReadCode!(T,m)();
    immutable string keyIsSetCode = null; //getColumnTypeKeyIsSetCode!(T,m)();
    immutable string isNullCode = propertyReadCode ~ " is null";
    immutable string copyFieldCode = getPropertyCopyCode!(T,m);
    //  pragma(msg, "property read: " ~ propertyReadCode);
    //  pragma(msg, "property write: " ~ propertyWriteCode);
    //  pragma(msg, "variant get: " ~ propertyVariantGetCode);
    immutable string readerFuncDef = "null";
    immutable string writerFuncDef = "null";
    immutable string getVariantFuncDef = 
        "\n" ~
            "function(Object obj) { \n" ~ 
            "    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
            "    return " ~ propertyVariantGetCode ~ "; \n" ~
            " }\n";
    immutable string setVariantFuncDef = 
        "\n" ~
            "function(Object obj, Variant value) { \n" ~ 
            "    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
            "    " ~ propertyVariantSetCode ~ "\n" ~
            " }\n";
    immutable string keyIsSetFuncDef = "\n" ~
        "function(Object obj) { \n" ~ 
            "    return false;\n" ~
            " }\n";
    immutable string isNullFuncDef = "\n" ~
        "function(Object obj) { \n" ~ 
            "    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
            "    return " ~ isNullCode ~ ";\n" ~
            " }\n";
    immutable string getObjectFuncDef = 
        "\n" ~
            "function(Object obj) { \n" ~ 
            "    writeln(\"Inside getObjectFunc\"); \n" ~
            "    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
            "    assert(entity !is null);\n" ~
            "    Object res = " ~ propertyObjectGetCode ~ "; \n" ~
            "    writeln(res is null ? \"obj is null\" : \"obj is not null\"); \n" ~
            "    return res; \n" ~
            " }\n";
    immutable string setObjectFuncDef = 
        "\n" ~
            "function(Object obj, Object value) { \n" ~ 
            "    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
            "    " ~ propertyObjectSetCode ~ "\n" ~
            " }\n";
    immutable string copyFuncDef = 
        "\n" ~
            "function(Object to, Object from) { \n" ~ 
            "    " ~ entityClassName ~ " toentity = cast(" ~ entityClassName ~ ")to; \n" ~
            "    " ~ entityClassName ~ " fromentity = cast(" ~ entityClassName ~ ")from; \n" ~
            "    " ~ copyFieldCode ~ "\n" ~
            " }\n";
    immutable string getCollectionFuncDef = "null";
    immutable string setCollectionFuncDef = "null";
    immutable string setObjectDelegateFuncDef = !isLazy ? "null" :
        "\n" ~
        "function(Object obj, Object delegate() loader) { \n" ~ 
            "    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
            "    " ~ getLazyPropertyObjectWriteCode!(T,m) ~ "\n" ~
            " }\n";
    immutable string setCollectionDelegateFuncDef = "null";
    immutable string isLoadedFuncDef = !isLazy ? "null" : 
    "\n" ~
        "function(Object obj) { \n" ~ 
            "    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
            "    return " ~ getLazyPropertyLoadedCode!(T,m) ~ ";\n" ~
            " }\n";

    return "    new PropertyInfo(" ~
            quoteString(propertyName) ~ ", " ~ 
            quoteString(columnName) ~ ", " ~ 
            typeName ~ ", " ~ 
            format("%s",length) ~ ", " ~ 
            "false, " ~ // id
            "false, " ~ // generated
            quoteBool(nullable) ~ ", " ~ 
            "RelationType.ManyToOne, " ~
            quoteString(referencedEntityName)  ~ ", " ~ 
            quoteString(referencedPropertyName)  ~ ", " ~ 
            readerFuncDef ~ ", " ~
            writerFuncDef ~ ", " ~
            getVariantFuncDef ~ ", " ~
            setVariantFuncDef ~ ", " ~
            keyIsSetFuncDef ~ ", " ~
            isNullFuncDef ~ ", " ~
            copyFuncDef ~ ", " ~
            "null, " ~ // generatorFunc
            getObjectFuncDef ~ ", " ~
            setObjectFuncDef ~ ", " ~
            getCollectionFuncDef ~ ", " ~
            setCollectionFuncDef ~ ", " ~
            setObjectDelegateFuncDef ~ ", " ~
            setCollectionDelegateFuncDef ~ ", " ~
            isLoadedFuncDef ~ ", " ~
            quoteBool(isLazy) ~ ", " ~ // lazy
            "false" ~ // collection
            ")";
}

/// generate source code for creation of OneToMany definition
string getOneToManyPropertyDef(T, immutable string m)() {
    immutable string referencedEntityName = getPropertyReferencedEntityName!(T,m);
    immutable string referencedClassName = getPropertyReferencedClassName!(T,m);
    immutable string referencedPropertyName = getOneToManyReferencedPropertyName!(T,m);
    static assert (referencedPropertyName != null, "OneToMany should have referenced property name parameter");
    immutable string entityClassName = fullyQualifiedName!T;
    immutable string propertyName = getPropertyName!(T,m)();
    static assert (propertyName != null, "Cannot determine property name for member " ~ m ~ " of type " ~ T.stringof);
    static assert (!hasOneOfMemberAnnotations!(T, m, Column, Id, Generated, Generator, OneToOne, ManyToMany, Embedded), entityClassName ~ "." ~ propertyName ~ ": OneToMany property cannot have Column, Id, Generated, Generator, OneToOne, ManyToMany or Embedded annotation");
    immutable string columnName = getJoinColumnName!(T, m)();
    immutable bool isCollection = isCollectionMember!(T,m);
    static assert (isCollection, "OneToMany property " ~ m ~ " should be array of objects or LazyCollection");
    static assert (columnName == null, "OneToMany property " ~ m ~ " should not have JoinColumn name");
    immutable bool isLazy = isLazyMember!(T,m) || isLazyCollectionMember!(T,m);
    immutable length = getColumnLength!(T, m);
    immutable bool hasNull = hasMemberAnnotation!(T,m, Null);
    immutable bool hasNotNull = hasMemberAnnotation!(T,m, NotNull);
    immutable bool nullable = hasNull ? true : (hasNotNull ? false : true); //canColumnTypeHoldNulls!(T.m)
    immutable bool unique = hasMemberAnnotation!(T, m, UniqueKey);
    immutable string typeName = "new EntityType(cast(immutable TypeInfo_Class)" ~ entityClassName ~ ".classinfo, \"" ~ entityClassName ~ "\")"; //getColumnTypeName!(T, m)();
    immutable string propertyReadCode = getPropertyReadCode!(T,m)();
    immutable string datasetReadCode = null; //getColumnTypeDatasetReadCode!(T,m)();
    immutable string propertyWriteCode = null; //getPropertyWriteCode!(T,m)();
    immutable string datasetWriteCode = null; //getColumnTypeDatasetWriteCode!(T,m)();
    immutable string propertyVariantSetCode = getCollectionPropertyVariantWriteCode!(T, m, referencedClassName); // getPropertyVariantWriteCode!(T,m)();
    immutable string propertyVariantGetCode = "Variant(" ~ propertyReadCode ~ " is null ? null : " ~ propertyReadCode ~ ")"; //getPropertyVariantReadCode!(T,m)();
    //pragma(msg, "propertyVariantGetCode: " ~ propertyVariantGetCode);
    //pragma(msg, "propertyVariantSetCode: " ~ propertyVariantSetCode);
    immutable string propertyObjectSetCode = getPropertyCollectionWriteCode!(T,m, referencedClassName); // getPropertyVariantWriteCode!(T,m)();
    immutable string propertyObjectGetCode = propertyReadCode; //getPropertyVariantReadCode!(T,m)();
    immutable string keyIsSetCode = null; //getColumnTypeKeyIsSetCode!(T,m)();
    immutable string isNullCode = propertyReadCode ~ " is null";
    immutable string copyFieldCode = getPropertyCopyCode!(T,m);
    //  pragma(msg, "property read: " ~ propertyReadCode);
    //  pragma(msg, "property write: " ~ propertyWriteCode);
    //  pragma(msg, "variant get: " ~ propertyVariantGetCode);
    immutable string readerFuncDef = "null";
    immutable string writerFuncDef = "null";
    immutable string getVariantFuncDef = 
        "\n" ~
            "function(Object obj) { \n" ~ 
            "    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
            "    return " ~ propertyVariantGetCode ~ "; \n" ~
            " }\n";
    immutable string setVariantFuncDef = 
        "\n" ~
            "function(Object obj, Variant value) { \n" ~ 
            "    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
            "    " ~ propertyVariantSetCode ~ "\n" ~
            " }\n";
    immutable string keyIsSetFuncDef = "\n" ~
        "function(Object obj) { \n" ~ 
            "    return false;\n" ~
            " }\n";
    immutable string isNullFuncDef = "\n" ~
        "function(Object obj) { \n" ~ 
            "    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
            "    return " ~ isNullCode ~ ";\n" ~
            " }\n";
    immutable string getObjectFuncDef = "null";
    immutable string setObjectFuncDef = "null";
    immutable string copyFuncDef = 
        "\n" ~
            "function(Object to, Object from) { \n" ~ 
            "    " ~ entityClassName ~ " toentity = cast(" ~ entityClassName ~ ")to; \n" ~
            "    " ~ entityClassName ~ " fromentity = cast(" ~ entityClassName ~ ")from; \n" ~
            "    " ~ copyFieldCode ~ "\n" ~
            " }\n";
    immutable string getCollectionFuncDef = 
        "\n" ~
        "function(Object obj) { \n" ~ 
            "    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
            "    assert(entity !is null);\n" ~
            "    return cast(Object[])" ~ propertyObjectGetCode ~ "; \n" ~
            " }\n";
    immutable string setCollectionFuncDef = 
        "\n" ~
        "function(Object obj, Object[] value) { \n" ~ 
            "    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
            "    " ~ propertyObjectSetCode ~ "\n" ~
            " }\n";
    immutable string setObjectDelegateFuncDef = "null";
    immutable string setCollectionDelegateFuncDef = !isLazy ? "null" :
    "\n" ~
        "function(Object obj, Object[] delegate() loader) { \n" ~ 
            "    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
            "    " ~ getLazyPropertyObjectWriteCode!(T,m) ~ "\n" ~
            " }\n";
    immutable string isLoadedFuncDef = !isLazy ? "null" : 
    "\n" ~
        "function(Object obj) { \n" ~ 
            "    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
            "    return " ~ getLazyPropertyLoadedCode!(T,m) ~ ";\n" ~
            " }\n";

    return "    new PropertyInfo(" ~
            quoteString(propertyName) ~ ", " ~ 
            quoteString(columnName) ~ ", " ~ 
            typeName ~ ", " ~ 
            format("%s",length) ~ ", " ~ 
            "false"  ~ ", " ~ // id
            "false"  ~ ", " ~ // generated
            quoteBool(nullable) ~ ", " ~ 
            "RelationType.OneToMany, " ~
            quoteString(referencedEntityName)  ~ ", " ~ 
            quoteString(referencedPropertyName)  ~ ", " ~ 
            readerFuncDef ~ ", " ~
            writerFuncDef ~ ", " ~
            getVariantFuncDef ~ ", " ~
            setVariantFuncDef ~ ", " ~
            keyIsSetFuncDef ~ ", " ~
            isNullFuncDef ~ ", " ~
            copyFuncDef ~ ", " ~
            "null, " ~ // generatorFunc
            getObjectFuncDef ~ ", " ~
            setObjectFuncDef ~ ", " ~
            getCollectionFuncDef ~ ", " ~
            setCollectionFuncDef ~ ", " ~
            setObjectDelegateFuncDef ~ ", " ~
            setCollectionDelegateFuncDef ~ ", " ~
            isLoadedFuncDef ~ ", " ~
            quoteBool(isLazy) ~ ", " ~ // lazy
            "true" ~ // is collection
            ")";
}

/// generate source code for creation of ManyToMany definition
string getManyToManyPropertyDef(T, immutable string m)() {
    immutable string referencedEntityName = getPropertyReferencedEntityName!(T,m);
    immutable string referencedClassName = getPropertyReferencedClassName!(T,m);
    immutable string entityClassName = fullyQualifiedName!T;
    immutable string propertyName = getPropertyName!(T,m);
    static assert (propertyName != null, "Cannot determine property name for member " ~ m ~ " of type " ~ T.stringof);
    static assert (!hasOneOfMemberAnnotations!(T, m, Column, Id, Generated, Generator, OneToOne, OneToMany, Embedded), entityClassName ~ "." ~ propertyName ~ ": ManyToMany property cannot have Column, Id, Generated, Generator, OneToOne, OneToMany or Embedded annotation");
    immutable string columnName = getJoinColumnName!(T, m);
    immutable string joinTableName = getJoinTableName!(T, m);
    immutable string joinColumn1 = getJoinTableColumn1!(T, m);
    immutable string joinColumn2 = getJoinTableColumn2!(T, m);
    immutable string joinTableCode = JoinTableInfo.generateJoinTableCode(joinTableName, joinColumn1, joinColumn2);
    immutable bool isCollection = isCollectionMember!(T,m);
    static assert (isCollection, "ManyToMany property " ~ m ~ " should be array of objects or LazyCollection");
    static assert (columnName == null, "ManyToMany property " ~ m ~ " should not have JoinColumn name");
    immutable bool isLazy = isLazyMember!(T,m) || isLazyCollectionMember!(T,m);
    immutable length = getColumnLength!(T, m);
    immutable bool hasNull = hasMemberAnnotation!(T,m, Null);
    immutable bool hasNotNull = hasMemberAnnotation!(T,m, NotNull);
    immutable bool nullable = hasNull ? true : (hasNotNull ? false : true); //canColumnTypeHoldNulls!(T.m)
    immutable bool unique = hasMemberAnnotation!(T, m, UniqueKey);
    immutable string typeName = "new EntityType(cast(immutable TypeInfo_Class)" ~ entityClassName ~ ".classinfo, \"" ~ entityClassName ~ "\")"; //getColumnTypeName!(T, m)();
    immutable string propertyReadCode = getPropertyReadCode!(T,m);
    immutable string datasetReadCode = null; //getColumnTypeDatasetReadCode!(T,m)();
    immutable string propertyWriteCode = null; //getPropertyWriteCode!(T,m)();
    immutable string datasetWriteCode = null; //getColumnTypeDatasetWriteCode!(T,m)();
    immutable string propertyVariantSetCode = getCollectionPropertyVariantWriteCode!(T, m, referencedClassName); // getPropertyVariantWriteCode!(T,m)();
    immutable string propertyVariantGetCode = "Variant(" ~ propertyReadCode ~ " is null ? null : " ~ propertyReadCode ~ ")"; //getPropertyVariantReadCode!(T,m)();
    //pragma(msg, "propertyVariantGetCode: " ~ propertyVariantGetCode);
    //pragma(msg, "propertyVariantSetCode: " ~ propertyVariantSetCode);
    immutable string propertyObjectSetCode = getPropertyCollectionWriteCode!(T,m, referencedClassName); // getPropertyVariantWriteCode!(T,m)();
    immutable string propertyObjectGetCode = propertyReadCode; //getPropertyVariantReadCode!(T,m)();
    immutable string keyIsSetCode = null; //getColumnTypeKeyIsSetCode!(T,m)();
    immutable string isNullCode = propertyReadCode ~ " is null";
    immutable string copyFieldCode = getPropertyCopyCode!(T,m);
    immutable string readerFuncDef = "null";
    immutable string writerFuncDef = "null";
    immutable string getVariantFuncDef = 
        "\n" ~
            "function(Object obj) { \n" ~ 
            "    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
            "    return " ~ propertyVariantGetCode ~ "; \n" ~
            " }\n";
    immutable string setVariantFuncDef = 
        "\n" ~
            "function(Object obj, Variant value) { \n" ~ 
            "    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
            "    " ~ propertyVariantSetCode ~ "\n" ~
            " }\n";
    immutable string keyIsSetFuncDef = "\n" ~
        "function(Object obj) { \n" ~ 
            "    return false;\n" ~
            " }\n";
    immutable string isNullFuncDef = "\n" ~
        "function(Object obj) { \n" ~ 
            "    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
            "    return " ~ isNullCode ~ ";\n" ~
            " }\n";
    immutable string getObjectFuncDef = "null";
    immutable string setObjectFuncDef = "null";
    immutable string copyFuncDef = 
        "\n" ~
            "function(Object to, Object from) { \n" ~ 
            "    " ~ entityClassName ~ " toentity = cast(" ~ entityClassName ~ ")to; \n" ~
            "    " ~ entityClassName ~ " fromentity = cast(" ~ entityClassName ~ ")from; \n" ~
            "    " ~ copyFieldCode ~ "\n" ~
            " }\n";
    immutable string getCollectionFuncDef = 
        "\n" ~
            "function(Object obj) { \n" ~ 
            "    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
            "    assert(entity !is null);\n" ~
            "    return cast(Object[])" ~ propertyObjectGetCode ~ "; \n" ~
            " }\n";
    immutable string setCollectionFuncDef = 
        "\n" ~
            "function(Object obj, Object[] value) { \n" ~ 
            "    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
            "    " ~ propertyObjectSetCode ~ "\n" ~
            " }\n";
    immutable string setObjectDelegateFuncDef = "null";
    immutable string setCollectionDelegateFuncDef = !isLazy ? "null" :
    "\n" ~
        "function(Object obj, Object[] delegate() loader) { \n" ~ 
            "    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
            "    " ~ getLazyPropertyObjectWriteCode!(T,m) ~ "\n" ~
            " }\n";
    immutable string isLoadedFuncDef = !isLazy ? "null" : 
    "\n" ~
        "function(Object obj) { \n" ~ 
            "    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
            "    return " ~ getLazyPropertyLoadedCode!(T,m) ~ ";\n" ~
            " }\n";

    return "    new PropertyInfo(" ~
            quoteString(propertyName) ~ ", " ~ 
            quoteString(columnName) ~ ", " ~ 
            typeName ~ ", " ~ 
            format("%s",length) ~ ", " ~ 
            "false"  ~ ", " ~ // id
            "false"  ~ ", " ~ // generated
            quoteBool(nullable) ~ ", " ~ 
            "RelationType.ManyToMany, " ~
            quoteString(referencedEntityName)  ~ ", " ~ 
            "null, " ~ //referencedPropertyName
            readerFuncDef ~ ", " ~
            writerFuncDef ~ ", " ~
            getVariantFuncDef ~ ", " ~
            setVariantFuncDef ~ ", " ~
            keyIsSetFuncDef ~ ", " ~
            isNullFuncDef ~ ", " ~
            copyFuncDef ~ ", " ~
            "null, " ~ // generatorFunc
            getObjectFuncDef ~ ", " ~
            setObjectFuncDef ~ ", " ~
            getCollectionFuncDef ~ ", " ~
            setCollectionFuncDef ~ ", " ~
            setObjectDelegateFuncDef ~ ", " ~
            setCollectionDelegateFuncDef ~ ", " ~
            isLoadedFuncDef ~ ", " ~
            quoteBool(isLazy) ~ ", " ~ // lazy
            "true" ~ ", " ~ // is collection
            joinTableCode ~
            ")";
}

/// generate source code for creation of Embedded definition
string getEmbeddedPropertyDef(T, immutable string m)() {
	immutable string referencedEntityName = getPropertyEmbeddedEntityName!(T,m);
	immutable string referencedClassName = getPropertyEmbeddedClassName!(T,m);
	immutable string entityClassName = fullyQualifiedName!T;
	immutable string propertyName = getPropertyName!(T,m);
	static assert (propertyName != null, "Cannot determine property name for member " ~ m ~ " of type " ~ T.stringof);
    static assert (!hasOneOfMemberAnnotations!(T, m, Column, Id, Generated, Generator, ManyToOne, ManyToMany, OneToOne), entityClassName ~ "." ~ propertyName ~ ": Embedded property cannot have Column, Id, Generated, OneToOne, ManyToOne, ManyToMany annotation");
    immutable string columnName = getColumnName!(T, m);
	immutable length = getColumnLength!(T, m);
	immutable bool hasNull = hasMemberAnnotation!(T, m, Null);
	immutable bool hasNotNull = hasMemberAnnotation!(T, m, NotNull);
	immutable bool nullable = hasNull ? true : (hasNotNull ? false : true); //canColumnTypeHoldNulls!(T.m)
	immutable bool unique = hasMemberAnnotation!(T, m, UniqueKey);
	immutable string typeName = "new EntityType(cast(immutable TypeInfo_Class)" ~ entityClassName ~ ".classinfo, \"" ~ entityClassName ~ "\")"; //getColumnTypeName!(T, m)();
	immutable string propertyReadCode = getPropertyReadCode!(T,m);
	immutable string datasetReadCode = null; //getColumnTypeDatasetReadCode!(T,m)();
	immutable string propertyWriteCode = null; //getPropertyWriteCode!(T,m)();
	immutable string datasetWriteCode = null; //getColumnTypeDatasetWriteCode!(T,m)();
	immutable string propertyVariantSetCode = getEmbeddedPropertyVariantWriteCode!(T, m, referencedClassName); // getPropertyVariantWriteCode!(T,m)();
	immutable string propertyVariantGetCode = "Variant(" ~ propertyReadCode ~ " is null ? null : " ~ propertyReadCode ~ ")"; //getPropertyVariantReadCode!(T,m)();
	immutable string propertyObjectSetCode = getPropertyObjectWriteCode!(T,m, referencedClassName); // getPropertyVariantWriteCode!(T,m)();
	immutable string propertyObjectGetCode = propertyReadCode; //getPropertyVariantReadCode!(T,m)();
	immutable string keyIsSetCode = null; //getColumnTypeKeyIsSetCode!(T,m)();
	immutable string isNullCode = propertyReadCode ~ " is null";
    immutable string copyFieldCode = getPropertyCopyCode!(T,m);
    //	pragma(msg, "property read: " ~ propertyReadCode);
	//	pragma(msg, "property write: " ~ propertyWriteCode);
	//	pragma(msg, "variant get: " ~ propertyVariantGetCode);
	immutable string readerFuncDef = "null";
	immutable string writerFuncDef = "null";
	immutable string getVariantFuncDef = 
		"\n" ~
		"function(Object obj) { \n" ~ 
			"    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
			"    return " ~ propertyVariantGetCode ~ "; \n" ~
			" }\n";
	immutable string setVariantFuncDef = 
		"\n" ~
		"function(Object obj, Variant value) { \n" ~ 
			"    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
			"    " ~ propertyVariantSetCode ~ "\n" ~
			" }\n";
	immutable string keyIsSetFuncDef = "\n" ~
		"function(Object obj) { \n" ~ 
			"    return false;\n" ~
			" }\n";
	immutable string isNullFuncDef = "\n" ~
		"function(Object obj) { \n" ~ 
			"    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
			"    return " ~ isNullCode ~ ";\n" ~
			" }\n";
	immutable string getObjectFuncDef = 
		"\n" ~
			"function(Object obj) { \n" ~ 
			"    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
			"    assert(entity !is null);\n" ~
			"    return " ~ propertyObjectGetCode ~ "; \n" ~
			" }\n";
	immutable string setObjectFuncDef = 
		"\n" ~
			"function(Object obj, Object value) { \n" ~ 
			"    " ~ entityClassName ~ " entity = cast(" ~ entityClassName ~ ")obj; \n" ~
			"    " ~ propertyObjectSetCode ~ "\n" ~
			" }\n";
    immutable string copyFuncDef = 
        "\n" ~
            "function(Object to, Object from) { \n" ~ 
            "    " ~ entityClassName ~ " toentity = cast(" ~ entityClassName ~ ")to; \n" ~
            "    " ~ entityClassName ~ " fromentity = cast(" ~ entityClassName ~ ")from; \n" ~
            "    " ~ copyFieldCode ~ "\n" ~
            " }\n";
	
	return "    new PropertyInfo(" ~ 
            quoteString(propertyName) ~ ", " ~ 
            quoteString(columnName) ~ ", " ~ 
            typeName ~ ", " ~ 
		    format("%s",length) ~ ", " ~ 
            "false, " ~ // id
			"false, " ~ // generated
            quoteBool(nullable) ~ ", " ~ 
			"RelationType.Embedded, " ~
			quoteString(referencedEntityName)  ~ ", " ~ 
		    "null, \n" ~
			readerFuncDef ~ ", " ~
			writerFuncDef ~ ", " ~
			getVariantFuncDef ~ ", " ~
			setVariantFuncDef ~ ", " ~
			keyIsSetFuncDef ~ ", " ~
			isNullFuncDef ~ ", " ~
            copyFuncDef ~ ", " ~
            "null, " ~ // generatorFunc
            getObjectFuncDef ~ ", " ~
			setObjectFuncDef ~ 
			")";
}

/// generate source code for creation of simple property definition
string getSimplePropertyDef(T, immutable string m)() {
	//getPropertyReferencedEntityName(
	immutable string entityClassName = fullyQualifiedName!T;
	immutable string propertyName = getPropertyName!(T,m);
	static assert (propertyName != null, "Cannot determine property name for member " ~ m ~ " of type " ~ T.stringof);
    static assert (!hasOneOfMemberAnnotations!(T, m, ManyToOne, OneToOne, ManyToMany, Embedded), entityClassName ~ "." ~ propertyName ~ ": simple property cannot have OneToOne, ManyToOne, ManyToMany or Embedded annotation");
    immutable bool isGenerated = hasMemberAnnotation!(T, m, Generated);
    immutable string generatorCode = getGeneratorCode!(T, m);
    immutable bool isId = hasMemberAnnotation!(T, m, Id) || isGenerated || generatorCode != null;
	immutable string columnName = getColumnName!(T, m);
    static assert(!isGenerated || generatorCode == null, T.stringof ~ "." ~ m ~ ": You cannot mix @Generated and @Generator for the same property");
	immutable length = getColumnLength!(T, m)();
	immutable bool hasNull = hasMemberAnnotation!(T,m,Null);
	immutable bool hasNotNull = hasMemberAnnotation!(T,m,NotNull);
	immutable bool nullable = hasNull ? true : (hasNotNull ? false : true); //canColumnTypeHoldNulls!(T.m)
	immutable bool unique = hasMemberAnnotation!(T, m, UniqueKey);
	immutable string typeName = getColumnTypeName!(T, m);
	immutable string propertyReadCode = getPropertyReadCode!(T,m);
	immutable string datasetReadCode = getColumnTypeDatasetReadCode!(T,m);
	immutable string propertyWriteCode = getPropertyWriteCode!(T,m);
	immutable string datasetWriteCode = getColumnTypeDatasetWriteCode!(T,m);
	immutable string propertyVariantSetCode = getPropertyVariantWriteCode!(T,m);
	immutable string propertyVariantGetCode = getPropertyVariantReadCode!(T,m);
	immutable string keyIsSetCode = getColumnTypeKeyIsSetCode!(T,m);
	immutable string isNullCode = getColumnTypeIsNullCode!(T,m);
    immutable string copyFieldCode = getPropertyCopyCode!(T,m);
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
    immutable string copyFuncDef = 
            "\n" ~
            "function(Object to, Object from) { \n" ~ 
            "    " ~ entityClassName ~ " toentity = cast(" ~ entityClassName ~ ")to; \n" ~
            "    " ~ entityClassName ~ " fromentity = cast(" ~ entityClassName ~ ")from; \n" ~
            "    " ~ copyFieldCode ~ "\n" ~
            " }\n";
    immutable string generatorFuncDef = generatorCode is null ? "null" :
            "\n" ~
            "function(Connection conn, const PropertyInfo property) { \n" ~ 
            "    return Variant(" ~ generatorCode ~ ");\n" ~
            "}\n";

	static assert (typeName != null, "Cannot determine column type for member " ~ m ~ " of type " ~ T.stringof);
	return "    new PropertyInfo(" ~ 
            quoteString(propertyName) ~ ", " ~
            quoteString(columnName) ~ ", " ~ 
            typeName ~ ", " ~ 
		    format("%s",length) ~ ", " ~ 
            quoteBool(isId)  ~ ", " ~ 
            quoteBool(isGenerated)  ~ ", " ~ 
            quoteBool(nullable) ~ ", " ~ 
			"RelationType.None, " ~ 
			"null, " ~ 
			"null, \n" ~
			readerFuncDef ~ ", " ~
			writerFuncDef ~ ", " ~
			getVariantFuncDef ~ ", " ~
			setVariantFuncDef ~ ", " ~
			keyIsSetFuncDef ~ ", " ~
            isNullFuncDef ~ ", " ~
            copyFuncDef ~ ", " ~
            generatorFuncDef ~
			")";
}

/// creates "new PropertyInfo(...)" code to create property metadata for member m of class T
string getPropertyDef(T, string m)() {
	immutable bool isEmbedded = hasMemberAnnotation!(T, m, Embedded);
	immutable bool isOneToOne = hasMemberAnnotation!(T, m, OneToOne);
    immutable bool isManyToOne = hasMemberAnnotation!(T, m, ManyToOne);
    immutable bool isManyToMany = hasMemberAnnotation!(T, m, ManyToMany);
    immutable bool isOneToMany = hasMemberAnnotation!(T, m, OneToMany);
    immutable bool isSimple = !isEmbedded && !isOneToOne && !isManyToOne && !isManyToMany && !isOneToMany;
	static if (isEmbedded) {
		//pragma(msg, getEmbeddedPropertyDef!(T, m)());
		return getEmbeddedPropertyDef!(T, m);
	} 
	static if (isSimple) {
		return getSimplePropertyDef!(T, m);
	} 
	static if (isOneToOne) {
		//pragma(msg, getOneToOnePropertyDef!(T, m)());
		return getOneToOnePropertyDef!(T, m);
	}
    static if (isManyToOne) {
        //pragma(msg, getOneToOnePropertyDef!(T, m)());
        return getManyToOnePropertyDef!(T, m);
    }
    static if (isOneToMany) {
        //pragma(msg, getOneToManyPropertyDef!(T, m));
        return getOneToManyPropertyDef!(T, m);
    }
    static if (isManyToMany) {
        //pragma(msg, getOneToOnePropertyDef!(T, m)());
        return getManyToManyPropertyDef!(T, m);
    }
}

string getEntityDef(T)() {
	string res;
	string generatedGettersSetters;

	string generatedEntityInfo;
	string generatedPropertyInfo;

    immutable string typeName = fullyQualifiedName!T;
	immutable bool isEntity = hasAnnotation!(T, Entity);

	static assert (hasOneOfAnnotations!(T, Entity, Embeddable), "Type " ~ typeName ~ " has neither @Entity nor @Embeddable annotation");
    //pragma(msg, "Entity type name: " ~ typeName);

	immutable string entityName = getEntityName!T();
	immutable string tableName = getTableName!T();

	//pragma(msg, "preparing entity : " ~ entityName);

	static assert (entityName != null, "Type " ~ typeName ~ " has no Entity name specified");
	static assert (tableName != null, "Type " ~ typeName ~ " has no Table name specified");

	generatedEntityInfo ~= "new EntityInfo(";
	generatedEntityInfo ~= "\"" ~ entityName ~ "\", ";
	generatedEntityInfo ~= "\"" ~ tableName ~ "\", ";
	generatedEntityInfo ~= hasAnnotation!(T, Embeddable) ? "true," : "false,";
	generatedEntityInfo ~= "[\n";

	//pragma(msg, entityName ~ " : " ~ ((hasHibernatedEmbeddableAnnotation!T) ? "true," : "false,"));

	foreach (m; __traits(allMembers, T)) {
		//pragma(msg, m);

		static if (__traits(compiles, (typeof(__traits(getMember, T, m))))){
			
//			static if (hasHibernatedAnnotation!(T, m)) {
//				pragma(msg, "Member " ~ m ~ " has known annotation");
//			}

			alias typeof(__traits(getMember, T, m)) ti;


			static if (hasHibernatedPropertyAnnotation!(T, m)) {
				
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

	//pragma(msg, "built entity : " ~ entityName);

	return generatedEntityInfo ~ "\n" ~ generatedGettersSetters;
}


string entityListDef(T ...)() {
	string res;
	foreach(t; T) {
		immutable string def = getEntityDef!t;

        //pragma(msg, def);

		if (res.length > 0)
			res ~= ",\n";
		res ~= def;
	}
	string code = 
		"static this() {\n" ~
		"    //writeln(\"starting static initializer\");\n" ~
		"    entities = [\n" ~ res ~ "];\n" ~
		"    EntityInfo [string] map;\n" ~
		"    EntityInfo [TypeInfo_Class] typemap;\n" ~
		"    foreach(e; entities) {\n" ~
		"        map[e.name] = e;\n" ~
		"        typemap[cast(TypeInfo_Class)e.classInfo] = e;\n" ~
        "    }\n" ~
		"    entityMap = map;\n" ~
		"    classMap = typemap;\n" ~
		"    //writeln(\"updating referenced entities\");\n" ~
		"    foreach(e; entities) {\n" ~
        "        foreach(p; e._properties) {\n" ~
		"            if (p.referencedEntityName !is null) {\n" ~
		"                //writeln(\"embedded entity \" ~ p.referencedEntityName);\n" ~
		"                enforceEx!HibernatedException((p.referencedEntityName in map) !is null, \"referenced entity not found in schema: \" ~ p.referencedEntityName);\n" ~
		"                p._referencedEntity = map[p.referencedEntityName];\n" ~
		"                if (p.referencedPropertyName !is null) {\n" ~
        "                    enforceEx!HibernatedException((p.referencedPropertyName in p._referencedEntity._propertyMap) !is null, \"embedded entity property not found in schema: \" ~ p.referencedEntityName);\n" ~
        "                    p._referencedProperty = p._referencedEntity._propertyMap[p.referencedPropertyName];\n" ~
		"				 }\n" ~
		"            }\n" ~
        "        }\n" ~
		"    }\n" ~
        "    //writeln(\"finished static initializer\");\n" ~
		"}";
	//pragma(msg, "built entity list");
    return code;
}

abstract class SchemaInfo : EntityMetaData {

	override @property size_t length() const {
		return getEntityCount();
	}
    override const(EntityInfo) opIndex(int index) const {
		return getEntity(index);
	}
    override const(EntityInfo) opIndex(string entityName) const {
		return findEntity(entityName);
	}

    override const(PropertyInfo) opIndex(string entityName, string propertyName) const {
		return findEntity(entityName).findProperty(propertyName);
	}

    override public Variant getPropertyValue(Object obj, string propertyName) const {
        return findEntityForObject(obj).getPropertyValue(obj, propertyName);
    }

    override public void setPropertyValue(Object obj, string propertyName, Variant value) const {
        findEntityForObject(obj).setPropertyValue(obj, propertyName, value);
    }

    private void appendCommaDelimitedList(ref string buf, string data) const {
        if (buf.length != 0)
            buf ~= ", ";
        buf ~= data;
    }

	public string getAllFieldListForUpdate(const EntityInfo ei, bool exceptKey = false) const {
		string query;
        foreach(pi; ei) {
            if (pi.key && exceptKey)
				continue;
			if (pi.embedded) {
                auto emei = pi.referencedEntity;
                appendCommaDelimitedList(query, getAllFieldListForUpdate(emei, exceptKey));
            } else if (pi.oneToOne || pi.manyToOne) {
                if (pi.columnName != null) {
                    // read FK column
                    appendCommaDelimitedList(query, pi.columnName ~ "=?");
                }
            } else if (pi.oneToMany || pi.manyToMany) {
                // skip
            } else {
                appendCommaDelimitedList(query, pi.columnName ~ "=?");
			}
		}
		return query;
	}
	
    override public string getAllFieldList(const EntityInfo ei, bool exceptKey = false) const {
		string query;
        foreach(pi; ei) {
            if (pi.key && exceptKey)
				continue;
			if (pi.embedded) {
                auto emei = pi.referencedEntity;
                appendCommaDelimitedList(query, getAllFieldList(emei, exceptKey));
            } else if (pi.oneToOne || pi.manyToOne) {
                if (pi.columnName != null) {
                    // read FK column
                    appendCommaDelimitedList(query, pi.columnName);
                }
            } else if (pi.oneToMany || pi.manyToMany) {
                // skip
            } else {
                appendCommaDelimitedList(query, pi.columnName);
			}
		}
		return query;
	}
	
    override public int getFieldCount(const EntityInfo ei, bool exceptKey) const {
        int count = 0;
        foreach(pi; ei) {
            if (pi.key && exceptKey)
                continue;
            if (pi.embedded) {
                auto emei = pi.referencedEntity;
                count += getFieldCount(emei, exceptKey);
            } else if (pi.oneToOne || pi.manyToOne) {
                if (pi.columnName != null) {
                    // read FK column
                    count++;
                }
            } else if (pi.oneToMany || pi.manyToMany) {
                // skip
            } else {
                count++;
            }
        }
        return count;
    }
    
    public string getAllFieldPlaceholderList(const EntityInfo ei, bool exceptKey = false) const {
		string query;
        foreach(pi; ei) {
            if (pi.key && exceptKey)
                continue;
            if (pi.embedded) {
                auto emei = pi.referencedEntity;
                appendCommaDelimitedList(query, getAllFieldPlaceholderList(emei));
            } else if (pi.oneToOne || pi.manyToOne) {
                if (pi.columnName != null) {
                    // read FK column
                    appendCommaDelimitedList(query, "?");
                }
            } else if (pi.oneToMany || pi.manyToMany) {
                // skip
            } else {
                appendCommaDelimitedList(query, "?");
			}
		}
		return query;
	}
	
    override public string getAllFieldList(string entityName, bool exceptKey) const {
        return getAllFieldList(findEntity(entityName), exceptKey);
    }

    override public int readAllColumns(Object obj, DataSetReader r, int startColumn) const {
        auto ei = findEntityForObject(obj);
		int columnCount = 0;
        foreach(pi; ei) {
			if (pi.embedded) {
                auto emei = pi.referencedEntity;
				Object em = emei.createEntity();
				int columnsRead = readAllColumns(em, r, startColumn + columnCount);
				pi.setObjectFunc(obj, em);
				columnCount += columnsRead;
            } else if (pi.oneToOne || pi.manyToOne) {
                if (pi.columnName !is null) {
                    Variant fk = r.getVariant(startColumn + columnCount);
                    // TODO: use FK
                    columnCount++;
                } else {
                    // TODO: plan reading
                }
            } else if (pi.oneToMany || pi.manyToMany) {
                // skip
            } else {
				pi.readFunc(obj, r, startColumn + columnCount);
				columnCount++;
			}
		}
		return columnCount;
	}

    override public int writeAllColumns(Object obj, DataSetWriter w, int startColumn, bool exceptKey = false) const {
        auto ei = findEntityForObject(obj);
		//writeln(ei.name ~ ".writeAllColumns");
		int columnCount = 0;
        foreach(pi; ei) {
            if (pi.key && exceptKey)
                continue;
            if (pi.embedded) {
                auto emei = pi.referencedEntity;
				//writeln("getting embedded entity " ~ emei.name);
				assert(pi.getObjectFunc !is null, "No getObjectFunc defined for embedded entity " ~ emei.name);
				Object em = pi.getObjectFunc(obj);
				if (em is null)
					em = emei.createEntity();
				assert(em !is null, "embedded object is null");
				//writeln("writing embedded entity " ~ emei.name);
				int columnsWritten = writeAllColumns(em, w, startColumn + columnCount);
				//writeln("written");
				columnCount += columnsWritten;
            } else if (pi.oneToOne || pi.manyToOne) {
                if (pi.columnName !is null) {
                    Object obj = pi.getObjectFunc(obj);
                    if (obj is null) {
                        w.setNull(startColumn + columnCount);
                    } else {
                        writeln("setting ID column for property " ~ pi.entity.name ~ "." ~ pi.propertyName);
                        if (pi.lazyLoad)
                            writeln("property has lazy loader");
                        writeln("reading ID variant " ~ pi.propertyName ~ " from object");
                        Variant id = pi.referencedEntity.getKey(obj);
                        writeln("setting parameter " ~ to!string(startColumn + columnCount));
                        w.setVariant(startColumn + columnCount, id);
                    }
                    columnCount++;
                }
                // skip
            } else if (pi.oneToMany || pi.manyToMany) {
                // skip
            } else {
				pi.writeFunc(obj, w, startColumn + columnCount);
				columnCount++;
			}
		}
		return columnCount;
	}

    override public string generateFindAllForEntity(string entityName) const {
        auto ei = findEntity(entityName);
        return "SELECT " ~ getAllFieldList(ei) ~ " FROM " ~ ei.tableName;
	}

    override public string generateFindByPkForEntity(const EntityInfo ei) const {
        return "SELECT " ~ getAllFieldList(ei) ~ " FROM " ~ ei.tableName ~ " WHERE " ~ ei.keyProperty.columnName ~ " = ?";
    }

    override public string generateInsertAllFieldsForEntity(const EntityInfo ei) const {
		return "INSERT INTO " ~ ei.tableName ~ "(" ~ getAllFieldList(ei) ~ ") VALUES (" ~ getAllFieldPlaceholderList(ei) ~ ")";
	}

    override public string generateInsertNoKeyForEntity(const EntityInfo ei) const {
		return "INSERT INTO " ~ ei.tableName ~ "(" ~ getAllFieldList(ei, true) ~ ") VALUES (" ~ getAllFieldPlaceholderList(ei, true) ~ ")";
	}

    override public string generateUpdateForEntity(const EntityInfo ei) const {
		return "UPDATE " ~ ei.tableName ~ " SET " ~ getAllFieldListForUpdate(ei, true) ~ " WHERE " ~ ei.getKeyProperty().columnName ~ "=?";
	}

    override public string generateFindByPkForEntity(string entityName) const {
        return generateFindByPkForEntity(findEntity(entityName));
    }

    override public string generateInsertAllFieldsForEntity(string entityName) const {
		return generateInsertAllFieldsForEntity(findEntity(entityName));
	}
}

class SchemaInfoImpl(T...) : SchemaInfo {
	static EntityInfo [string] entityMap;
	static EntityInfo [] entities;
	static EntityInfo [TypeInfo_Class] classMap;
    //pragma(msg, entityListDef!(T)());
    mixin(entityListDef!(T)());

    override public int getEntityCount() const { return cast(int)entities.length; }

    override public const(EntityInfo[]) getEntities() const  { return entities; }
    override public const(EntityInfo[string]) getEntityMap() const  { return entityMap; }
    override public const(EntityInfo [TypeInfo_Class]) getClassMap() const  { return classMap; }

    override int opApply(int delegate(ref const EntityInfo) dg) const { 
        int result = 0; 
        for (int i = 0; i < entities.length; i++) { 
            result = dg(entities[i]); 
            if (result) break; 
        } 
        return result; 
    }

    override public const(EntityInfo) findEntity(string entityName) const  { 
        enforceEx!HibernatedException((entityName in entityMap) !is null, "Cannot find entity by name " ~ entityName);
        return entityMap[entityName]; 
    }

    override public const(EntityInfo) findEntity(TypeInfo_Class entityClass) const { 
        enforceEx!HibernatedException((entityClass in classMap) !is null, "Cannot find entity by class " ~ entityClass.toString());
        return classMap[entityClass]; 
    }

    override public const(EntityInfo) getEntity(int entityIndex) const { 
        enforceEx!HibernatedException(entityIndex >= 0 && entityIndex < entities.length, "Invalid entity index " ~ to!string(entityIndex));
        return entities[entityIndex]; 
    }

    override public Object createEntity(string entityName) const { 
        enforceEx!HibernatedException((entityName in entityMap) !is null, "Cannot find entity by name " ~ entityName);
        return entityMap[entityName].createEntity(); 
    }

    override public const(EntityInfo) findEntityForObject(Object obj) const {
        enforceEx!HibernatedException((obj.classinfo in classMap) !is null, "Cannot find entity by class " ~ obj.classinfo.toString());
        return classMap[obj.classinfo];
    }
    this() {
        // update entity._metadata reference
        foreach(e; entities) {
            e._metadata = this;
            int columnOffset = 0;
            foreach(p; e._properties) {
                if (p.manyToMany) {
                    p.updateJoinTable();
                }
                p._columnOffset = columnOffset;
                if (p.embedded) {
                    auto emei = p.referencedEntity;
                    columnOffset += e.metadata.getFieldCount(emei, false);
                } else if (p.oneToOne || p.manyToOne) {
                    if (p.columnName != null) {
                        // read FK column
                        columnOffset++;
                    }
                } else {
                    columnOffset++;
                }
            }
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


	EntityInfo entity = new EntityInfo("user", "users",  false, [
	                                                             new PropertyInfo("id", "id", new NumberType(10,false,SqlType.INTEGER), 0, true, true, false, RelationType.None, null, null, null, null, null, null, null, null, null)
	                                                     ], null);

	assert(entity.properties.length == 1);


//	immutable string info = getEntityDef!User();
//	immutable string infos = entityListDef!(User, Customer)();

	EntityInfo ei = new EntityInfo("User", "users", false, [
                                                            new PropertyInfo("id", "id_column", new NumberType(10,false,SqlType.INTEGER), 0, true, true, false, RelationType.None, null, null, null, null, null, null, null, null, null),
                                                            new PropertyInfo("name", "name_column", new StringType(), 0, false, false, false, RelationType.None, null, null, null, null, null, null, null, null, null),
                                                            new PropertyInfo("flags", "flags", new StringType(), 0, false, false, true, RelationType.None, null, null, null, null, null, null, null, null, null),
                                                            new PropertyInfo("login", "login", new StringType(), 0, false, false, true, RelationType.None, null, null, null, null, null, null, null, null, null),
                                                            new PropertyInfo("testColumn", "testcolumn", new NumberType(10,false,SqlType.INTEGER), 0, false, false, true, RelationType.None, null, null, null, null, null, null, null, null, null)], null);

	//void function(User, DataSetReader, int) readFunc = function(User entity, DataSetReader reader, int index) { };

	assert(ei.findProperty("name").columnName == "name_column");
	assert(ei.getProperties()[0].columnName == "id_column");
	assert(ei.getProperty(2).propertyName == "flags");
	assert(ei.getPropertyCount == 5);

	EntityInfo[] entities3 =  [
	                           new EntityInfo("User", "users", false, [
	                                        new PropertyInfo("id", "id_column", new NumberType(10,false,SqlType.INTEGER), 0, true, true, false, RelationType.None, null, null, null, null, null, null, null, null, null),
	                                        new PropertyInfo("name", "name_column", new StringType(), 0, false, false, false, RelationType.None, null, null, null, null, null, null, null, null, null),
	                                        new PropertyInfo("flags", "flags", new StringType(), 0, false, false, true, RelationType.None, null, null, null, null, null, null, null, null, null),
	                                        new PropertyInfo("login", "login", new StringType(), 0, false, false, true, RelationType.None, null, null, null, null, null, null, null, null, null),
	                                        new PropertyInfo("testColumn", "testcolumn", new NumberType(10,false,SqlType.INTEGER), 0, false, false, true, RelationType.None, null, null, null, null, null, null, null, null, null)], null)
	                                                                 ,
	                           new EntityInfo("Customer", "customer", false, [
	                                               new PropertyInfo("id", "id", new NumberType(10,false,SqlType.INTEGER), 0, true, true, true, RelationType.None, null, null, null, null, null, null, null, null, null),
                                                   new PropertyInfo("name", "name", new StringType(), 0, false, false, true, RelationType.None, null, null, null, null, null, null, null, null, null)], null)
	                                                                 ];


}


