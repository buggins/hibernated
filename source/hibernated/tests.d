/**
 * HibernateD - Object-Relation Mapping for D programming language, with interface similar to Hibernate. 
 * 
 * Hibernate documentation can be found here:
 * $(LINK http://hibernate.org/docs)$(BR)
 * 
 * Source file hibernated/tests.d.
 *
 * This module contains unit tests for functional testing on real DB.
 * 
 * Copyright: Copyright 2013
 * License:   $(LINK www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Author:   Vadim Lopatin
 */
module hibernated.tests;

private import std.algorithm;
private import std.conv;
private import std.stdio;
private import std.datetime;
private import std.typecons;
private import std.exception;
private import std.variant;

private import ddbc.core : Connection, DataSource, Statement;

private import hibernated.core;

version(unittest) {

    //@Entity
    @Table("users") // to override table name - "users" instead of default "user"
    class User {
        
        //@Generated
        long id;
        
        string name;
        
        // property column
        private long _flags;
        @Null // override NotNull which is inferred from long type
        @property void flags(long v) { _flags = v; }
        @property ref long flags() { return _flags; }

        // getter/setter property
        string comment;
        // @Column -- not mandatory, will be deduced
        @Null // override default nullability of string with @Null (instead of using String)
        @Column(null, 1024) // override default length, autogenerate column name)
        string getComment() { return comment; }
        void setComment(string v) { comment = v; }
        
        //@ManyToOne -- not mandatory, will be deduced
        //@JoinColumn("customer_fk")
        Customer customer;
        
        @ManyToMany
        LazyCollection!Role roles;
        
        override string toString() {
            return "id=" ~ to!string(id) ~ ", name=" ~ name ~ ", flags=" ~ to!string(flags) ~ ", comment=" ~ comment ~ ", customerId=" ~ (customer is null ? "NULL" : customer.toString());
        }
        
    }
    
    
    //@Entity
    @Table("customers") // to override table name - "customers" instead of default "customer"
    class Customer {
        //@Generated
        int id;
        // @Column -- not mandatory, will be deduced
        string name;

        // deduced as @Embedded automatically
        Address address;
        
        //@ManyToOne -- not mandatory, will be deduced
        //@JoinColumn("account_type_fk")
        Lazy!AccountType accountType;
        
        //        @OneToMany("customer")
        //        LazyCollection!User users;
        
        //@OneToMany("customer") -- not mandatory, will be deduced
        private User[] _users;
        @property User[] users() { return _users; }
        @property void users(User[] value) { _users = value; }
        
        this() {
            address = new Address();
        }
        override string toString() {
            return "id=" ~ to!string(id) ~ ", name=" ~ name ~ ", address=" ~ address.toString();
        }
    }

    static assert(isEmbeddedObjectMember!(Customer, "address"));
    
    @Embeddable
    class Address {
        hibernated.type.String zip;
        hibernated.type.String city;
        hibernated.type.String streetAddress;
        @Transient // mark field with @Transient to avoid creating column for it
        string someNonPersistentField;

        override string toString() {
            return " zip=" ~ zip ~ ", city=" ~ city ~ ", streetAddress=" ~ streetAddress;
        }
    }
    
    @Entity // need to have at least one annotation to import automatically from module
    class AccountType {
        //@Generated
        int id;
        string name;
    }
    
    //@Entity 
    class Role {
        //@Generated
        int id;
        string name;
        @ManyToMany 
        LazyCollection!User users;
    }
    
    //@Entity
    //@Table("t1")
    class T1 {
        //@Id 
        //@Generated
        int id;
        
        //@NotNull 
        @UniqueKey
        string name;
        
        // property column
        private long _flags;
        // @Column -- not mandatory, will be deduced
        @property long flags() { return _flags; }
        @property void flags(long v) { _flags = v; }
        
        // getter/setter property
        private string comment;
        // @Column -- not mandatory, will be deduced
        @Null
        string getComment() { return comment; }
        void setComment(string v) { comment = v; }
        
        
        override string toString() {
            return "id=" ~ to!string(id) ~ ", name=" ~ name ~ ", flags=" ~ to!string(flags) ~ ", comment=" ~ comment;
        }
    }
    
    @Entity
    static class GeneratorTest {
        //@Generator("std.uuid.randomUUID().toString()")
        @Generator(UUID_GENERATOR)
        string id;
        string name;
    }
    
    // a @Generator on a property that isn't the key: id stays the key (#104)
    @Entity
    static class GeneratedTokenTest {
        @Id long id;
        @Generator(UUID_GENERATOR)
        string token;
        string name;
    }

    // no @Id: the property named id is the key, not the one with a @Generator (#104)
    @Entity
    static class GeneratedTokenNoIdTest {
        long id;
        @Generator(UUID_GENERATOR)
        string token;
    }

    // @Id after another member: a property named id isn't a second key (hasAnyKeyPropertyAnnotation
    // looked at the first public member only, #104)
    @Entity
    static class IdNotFirstTest {
        string name;
        @Id long code;
        long id;
    }

    @Entity
    static class TypeTest {
        //@Generated
        int id;
        string string_field;
        hibernated.type.String nullable_string_field;
        byte byte_field;
        short short_field;
        int int_field;
        long long_field;
        ubyte ubyte_field;
        ushort ushort_field;
        ulong ulong_field;
        DateTime datetime_field;
        Date date_field;
        TimeOfDay time_field;
        Byte nullable_byte_field;
        Short nullable_short_field;
        Int nullable_int_field;
        Long nullable_long_field;
        Ubyte nullable_ubyte_field;
        Ushort nullable_ushort_field;
        Ulong nullable_ulong_field;
        NullableDateTime nullable_datetime_field;
        NullableDate nullable_date_field;
        NullableTimeOfDay nullable_time_field;
        float float_field;
        double double_field;
        Float nullable_float_field;
        Double nullable_double_field;
        byte[] byte_array_field;
        ubyte[] ubyte_array_field;
    }

    // a bool property, set from integers (#124)
    @Entity
    static class BoolTest {
        int id;
        bool flag;
    }

    // transactions after errors (#135)
    @Entity
    static class TxStateTest {
        @Id
        int id;
        string name;
    }

    // a generator that returns no value (#118)
    @Entity
    static class EmptyGeneratorTest {
        @Generator("Variant()")
        string id;
        string name;
    }

    // the one nullable type TypeTest lacks
    @Entity
    static class NullableUintTest {
        int id;
        Uint value;
    }

    // Nullable properties through a getter/setter pair and an @property pair (#117)
    @Entity
    static class NullableAccessorTest {
        int id;
        private Nullable!int _count;
        private Nullable!Date _day;
        Nullable!int getCount() { return _count; }
        void setCount(Nullable!int v) { _count = v; }
        @property Nullable!Date day() { return _day; }
        @property void day(Nullable!Date v) { _day = v; }
    }
    
    import ddbc.drivers.sqliteddbc;
    import ddbc.common;
    import hibernated.dialects.mysqldialect;
    import hibernated.dialects.sqlitedialect;
    import hibernated.dialects.pgsqldialect;

    
    string[] UNIT_TEST_FILL_TABLES_SCRIPT = 
        [
         "INSERT INTO role (name) VALUES ('admin')",
         "INSERT INTO role (name) VALUES ('viewer')",
         "INSERT INTO role (name) VALUES ('editor')",
         "INSERT INTO account_type (name) VALUES ('Type1')",
         "INSERT INTO account_type (name) VALUES ('Type2')",
         "INSERT INTO customers (name, zip, account_type_fk) VALUES ('customer 1', '12345', 1)",
         "INSERT INTO customers (name, zip) VALUES ('customer 2', '54321')",
         "INSERT INTO customers (name, street_address, account_type_fk) VALUES ('customer 3', 'Baker Street, 24', 2)",
         "INSERT INTO users (name, flags, comment, customer_fk) VALUES ('user 1', 11, 'comments for user 1', 1)",
         "INSERT INTO users (name, flags, comment, customer_fk) VALUES ('user 2', 22, 'this user belongs to customer 1', 1)",
         "INSERT INTO users (name, flags, comment, customer_fk) VALUES ('user 3', NULL, 'this user belongs to customer 2', 2)",
         "INSERT INTO users (name, flags, comment, customer_fk) VALUES ('user 4', 44,   NULL, 3)",
         "INSERT INTO users (name, flags, comment, customer_fk) VALUES ('test user 5', 55, 'this user belongs to customer 3, too', 3)",
         "INSERT INTO users (name, flags, comment, customer_fk) VALUES ('test user 6', 66, 'for checking of Nullable!long reading', null)",
         "INSERT INTO person_info (id, flags) VALUES (3, 123)",
         "INSERT INTO person_info (id, flags) VALUES (4, 234)",
         "INSERT INTO person_info (id, flags) VALUES (5, 345)",
         "INSERT INTO person_info2 (id, flags, person_info_fk) VALUES (10, 1, 3)",
         "INSERT INTO person_info2 (id, flags, person_info_fk) VALUES (11, 2, 4)",
         "INSERT INTO person (first_name, last_name, more_info_fk) VALUES ('Andrei', 'Alexandrescu', 3)",
         "INSERT INTO person (first_name, last_name, more_info_fk) VALUES ('Walter', 'Bright', 4)",
         "INSERT INTO person (first_name, last_name, more_info_fk) VALUES ('John', 'Smith', 5)",
         "INSERT INTO role_users (role_fk, user_fk) VALUES (1, 1)",
         "INSERT INTO role_users (role_fk, user_fk) VALUES (2, 1)",
         "INSERT INTO role_users (role_fk, user_fk) VALUES (2, 2)",
         "INSERT INTO role_users (role_fk, user_fk) VALUES (2, 3)",
         "INSERT INTO role_users (role_fk, user_fk) VALUES (3, 2)",
         "INSERT INTO role_users (role_fk, user_fk) VALUES (3, 3)",
         "INSERT INTO role_users (role_fk, user_fk) VALUES (3, 5)",
         ];

    /// Runs `queries` one after the other (ddbc no longer has this helper either).
    void unitTestExecuteBatch(Connection conn, string[] queries) {
        Statement stmt = conn.createStatement();
        scope(exit) stmt.close();
        foreach (query; queries)
            stmt.executeUpdate(query);
    }

    /// Fills the test tables, which `updateDBSchema` creates from the entity metadata.
    void fillTestTables() {
        DataSource connectionPool = getUnitTestDataSource();
        if (connectionPool is null)
            return; // DB tests disabled
        Connection conn = connectionPool.getConnection();
        scope(exit) conn.close();
        unitTestExecuteBatch(conn, UNIT_TEST_FILL_TABLES_SCRIPT);
    }

    // ddbc no longer defines these switches and data sources (buggins/ddbc#111): the unit tests use SQLite
    // in memory when it's built in. MySQL and PostgreSQL are tested by hdtest, against real servers (#104).
    version (USE_SQLITE)
        immutable bool SQLITE_TESTS_ENABLED = true;
    else
        immutable bool SQLITE_TESTS_ENABLED = false;

    static if (SQLITE_TESTS_ENABLED) {
        /// An in-memory database: the pool keeps its one connection, and with it the data. So only one
        /// connection may be open at a time: opening a second one fails at once (wait time-out 0), where it
        /// happens. Time-to-live 0 (no limit) keeps the connection; the pool would still replace it if it broke
        /// (e.g. failed its check), and the tests after that would find an empty database.
        DataSource createUnitTestSQLITEDataSource() {
            import ddbc.common : createConnectionPool;
            return createConnectionPool("sqlite::memory:", null, 1, 0, 0);
        }
    }

    immutable bool DB_TESTS_ENABLED = SQLITE_TESTS_ENABLED;


    package DataSource _unitTestConnectionPool;
    /// will return null if DB tests are disabled
    DataSource getUnitTestDataSource() {
        if (_unitTestConnectionPool is null) {
            static if (SQLITE_TESTS_ENABLED) {
                pragma(msg, "Will use SQLite for HibernateD unit tests");
                _unitTestConnectionPool = createUnitTestSQLITEDataSource();
            }
        }
        return _unitTestConnectionPool;
    }
    Dialect getUnitTestDialect() {

        static if (SQLITE_TESTS_ENABLED) {
            return new SQLiteDialect();
        } else {
            return null; // disabled
        }
    }

    void closeUnitTestDataSource() {
//        if (!_unitTestConnectionPool is null) {
//            _unitTestConnectionPool.close();
//            _unitTestConnectionPool = null;
//        }
    }
}


unittest {
    // CREATE TABLE text of the MySQL and PostgreSQL dialects: no server needed (hdtest runs them against servers)
    EntityMetaData schema = new SchemaInfoImpl!(User, Customer, AccountType, T1, TypeTest, Address, Role, GeneratorTest, Person, MoreInfo, EvenMoreInfo);
    DBInfo mysql = new DBInfo(new MySQLDialect(), schema);
    assert(mysql["users"].getCreateTableSQL() == "CREATE TABLE users (id BIGINT NOT NULL PRIMARY KEY AUTO_INCREMENT, name VARCHAR(255) NOT NULL, flags BIGINT NULL, comment VARCHAR(1024) NULL, customer_fk INT NULL)");
    assert(mysql["customers"].getCreateTableSQL() == "CREATE TABLE customers (id INT NOT NULL PRIMARY KEY AUTO_INCREMENT, name VARCHAR(255) NOT NULL, zip VARCHAR(255) NULL, city VARCHAR(255) NULL, street_address VARCHAR(255) NULL, account_type_fk INT NULL)");
    assert(mysql["account_type"].getCreateTableSQL() == "CREATE TABLE account_type (id INT NOT NULL PRIMARY KEY AUTO_INCREMENT, name VARCHAR(255) NOT NULL)");
    assert(mysql["t1"].getCreateTableSQL() == "CREATE TABLE t1 (id INT NOT NULL PRIMARY KEY AUTO_INCREMENT, name VARCHAR(255) NOT NULL, flags BIGINT NOT NULL, comment VARCHAR(255) NULL)");
    assert(mysql["role"].getCreateTableSQL() == "CREATE TABLE role (id INT NOT NULL PRIMARY KEY AUTO_INCREMENT, name VARCHAR(255) NOT NULL)");
    assert(mysql["generator_test"].getCreateTableSQL() == "CREATE TABLE generator_test (id VARCHAR(255) NOT NULL PRIMARY KEY, name VARCHAR(255) NOT NULL)");
    assert(mysql["role_users"].getCreateTableSQL() == "CREATE TABLE role_users (role_fk INT NOT NULL, user_fk BIGINT NOT NULL, PRIMARY KEY (role_fk, user_fk), UNIQUE INDEX role_users_reverse_index (user_fk, role_fk))");
    DBInfo pgsql = new DBInfo(new PGSQLDialect(), schema);
    assert(pgsql["users"].getCreateTableSQL() == "CREATE TABLE users (id BIGSERIAL PRIMARY KEY, name TEXT NOT NULL, flags BIGINT NULL, comment TEXT NULL, customer_fk INT NULL)");
    assert(pgsql["customers"].getCreateTableSQL() == "CREATE TABLE customers (id SERIAL PRIMARY KEY, name TEXT NOT NULL, zip TEXT NULL, city TEXT NULL, street_address TEXT NULL, account_type_fk INT NULL)");
    assert(pgsql["account_type"].getCreateTableSQL() == "CREATE TABLE account_type (id SERIAL PRIMARY KEY, name TEXT NOT NULL)");
    assert(pgsql["t1"].getCreateTableSQL() == "CREATE TABLE t1 (id SERIAL PRIMARY KEY, name TEXT NOT NULL, flags BIGINT NOT NULL, comment TEXT NULL)");
    assert(pgsql["role"].getCreateTableSQL() == "CREATE TABLE role (id SERIAL PRIMARY KEY, name TEXT NOT NULL)");
    assert(pgsql["generator_test"].getCreateTableSQL() == "CREATE TABLE generator_test (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL)");
    assert(pgsql["role_users"].getCreateTableSQL() == "CREATE TABLE role_users (role_fk INT NOT NULL, user_fk BIGINT NOT NULL, PRIMARY KEY (role_fk, user_fk), UNIQUE (user_fk, role_fk))");
}

unittest {
    // Nullable properties set from a Variant: a null Variant makes them null (#117)
    EntityMetaData schema = new SchemaInfoImpl!(TypeTest);
    auto info = schema["TypeTest"];
    auto e = new TypeTest();
    static foreach (f; [
            ["nullable_byte_field", "cast(byte) -5"], ["nullable_short_field", "cast(short) -300"],
            ["nullable_int_field", "-70000"], ["nullable_long_field", "-5_000_000_000L"],
            ["nullable_ubyte_field", "cast(ubyte) 200"], ["nullable_ushort_field", "cast(ushort) 60000"],
            ["nullable_ulong_field", "10_000_000_000UL"], ["nullable_float_field", "1.5f"],
            ["nullable_double_field", "2.25"], ["nullable_datetime_field", "DateTime(2019, 9, 15, 15, 18, 51)"],
            ["nullable_date_field", "Date(2019, 9, 15)"], ["nullable_time_field", "TimeOfDay(15, 18, 51)"]]) {{
        info.setPropertyValue(e, f[0], Variant(mixin(f[1])));
        assert(!__traits(getMember, e, f[0]).isNull && __traits(getMember, e, f[0]).get == mixin(f[1]), f[0]);
        info.setPropertyValue(e, f[0], Variant(null));
        assert(__traits(getMember, e, f[0]).isNull, f[0]);
    }}

    EntityMetaData uintSchema = new SchemaInfoImpl!(NullableUintTest);
    auto u = new NullableUintTest();
    uintSchema["NullableUintTest"].setPropertyValue(u, "value", Variant(4_000_000_000U));
    assert(u.value.get == 4_000_000_000U);
    uintSchema["NullableUintTest"].setPropertyValue(u, "value", Variant(null));
    assert(u.value.isNull);

    EntityMetaData accessorSchema = new SchemaInfoImpl!(NullableAccessorTest);
    auto ai = accessorSchema["NullableAccessorTest"];
    auto a = new NullableAccessorTest();
    ai.setPropertyValue(a, "count", Variant(5));
    assert(a.getCount().get == 5);
    assert(ai.getPropertyValue(a, "count") == 5);
    ai.setPropertyValue(a, "count", Variant(7L)); // a long Variant, as ddbc returns for integers (generated keys)
    assert(a.getCount().get == 7);
    ai.setPropertyValue(a, "count", Variant(null));
    assert(a.getCount().isNull);
    assert(ai.getPropertyValue(a, "count") == null);
    ai.setPropertyValue(a, "day", Variant(Date(2019, 9, 15)));
    assert(a.day.get == Date(2019, 9, 15));
    assert(ai.getPropertyValue(a, "day") == Date(2019, 9, 15));
    ai.setPropertyValue(a, "day", Variant(null));
    assert(a.day.isNull);
    assert(ai.getPropertyValue(a, "day") == null);
}

unittest {
    // an empty Variant (no value) sets a property like Variant(null) does (#118)
    import std.conv : ConvOverflowException;
    import std.exception : assertThrown;
    EntityMetaData schema = new SchemaInfoImpl!(TypeTest);
    auto info = schema["TypeTest"];
    auto e = new TypeTest();
    e.string_field = "a";
    e.int_field = 5;
    e.ulong_field = 6;
    e.date_field = Date(2019, 9, 15);
    e.time_field = TimeOfDay(15, 18, 51);
    e.ubyte_array_field = [1, 2];
    e.nullable_int_field = 7;
    e.nullable_date_field = Date(2019, 9, 15);
    foreach (name; ["string_field", "int_field", "ulong_field", "date_field", "time_field", "ubyte_array_field",
            "nullable_int_field", "nullable_date_field"])
        info.setPropertyValue(e, name, Variant());
    assert(e.string_field is null && e.int_field == 0 && e.ulong_field == 0);
    assert(e.date_field == Date.init && e.time_field == TimeOfDay.init && e.ubyte_array_field is null);
    assert(e.nullable_int_field.isNull && e.nullable_date_field.isNull);

    // integer properties convert with a range check (#119)
    info.setPropertyValue(e, "long_field", Variant(long.max));
    assert(e.long_field == long.max);
    info.setPropertyValue(e, "ulong_field", Variant(ulong.max));
    assert(e.ulong_field == ulong.max);
    info.setPropertyValue(e, "ulong_field", Variant(5L)); // ddbc returns integers (generated keys) as long
    assert(e.ulong_field == 5);
    info.setPropertyValue(e, "byte_field", Variant(-128L));
    assert(e.byte_field == -128);
    assertThrown!ConvOverflowException(info.setPropertyValue(e, "long_field", Variant(ulong.max)));
    assertThrown!ConvOverflowException(info.setPropertyValue(e, "ulong_field", Variant(-1L)));
    assertThrown!ConvOverflowException(info.setPropertyValue(e, "int_field", Variant(uint.max)));
    assertThrown!ConvOverflowException(info.setPropertyValue(e, "byte_field", Variant(128)));
    assertThrown!ConvOverflowException(info.setPropertyValue(e, "ushort_field", Variant(-1)));
    assertThrown!ConvOverflowException(info.setPropertyValue(e, "nullable_long_field", Variant(ulong.max)));
    assertThrown!ConvOverflowException(info.setPropertyValue(e, "nullable_ubyte_field", Variant(256)));
    assert(e.long_field == long.max && e.ulong_field == 5 && e.byte_field == -128); // unchanged
    assert(e.nullable_long_field.isNull);

    // byte arrays of either signedness
    info.setPropertyValue(e, "byte_array_field", Variant(cast(ubyte[]) [1, 255]));
    assert(e.byte_array_field == [1, -1]);
    info.setPropertyValue(e, "ubyte_array_field", Variant(cast(byte[]) [-1]));
    assert(e.ubyte_array_field == [255]);

    // keys above long.max stay ulongs, equal keys of different integer types normalize to the same key
    assert(hibernated.session.normalize(Variant(ulong.max)).get!ulong == ulong.max);
    assert(hibernated.session.normalize(Variant(5UL)) == hibernated.session.normalize(Variant(5)));

    // an empty string or array is a value, not NULL
    info.setPropertyValue(e, "nullable_string_field", Variant(""));
    assert(!e.nullable_string_field.isNull);
    info.setPropertyValue(e, "nullable_string_field", Variant(null));
    assert(e.nullable_string_field.isNull);
}

unittest {
    // a key generator that returns no value fails save instead of storing a default key (#118)
    EntityMetaData schema = new SchemaInfoImpl!(EmptyGeneratorTest);
    DataSource ds = getUnitTestDataSource();
    if (ds is null)
        return; // DB tests disabled
    SessionFactory factory = new SessionFactoryImpl(schema, getUnitTestDialect(), ds);
    scope(exit) factory.close();
    Session sess = factory.openSession();
    scope(exit) sess.close();
    auto e = new EmptyGeneratorTest();
    e.name = "x";
    try {
        sess.save(e);
        assert(false, "save with an empty generated key must fail");
    } catch (HibernatedException ex) {
        assert(ex.msg == "The key generator returned no key for EmptyGeneratorTest", ex.msg);
    }
    assert(e.id is null);
}

unittest {
    // which property is the key (#104)
    EntityMetaData schema = new SchemaInfoImpl!(GeneratorTest, GeneratedTokenTest, GeneratedTokenNoIdTest, IdNotFirstTest);
    assert(schema["GeneratorTest"].getKeyProperty().propertyName == "id");
    assert(!schema["GeneratorTest"]["id"].generated); // the generator makes the values, not the database
    assert(schema["GeneratorTest"]["id"].generatorFunc !is null);
    assert(schema["GeneratedTokenTest"].getKeyProperty().propertyName == "id");
    assert(!schema["GeneratedTokenTest"]["token"].key);
    assert(!schema["GeneratedTokenTest"]["token"].generated);
    assert(schema["GeneratedTokenNoIdTest"].getKeyProperty().propertyName == "id");
    assert(schema["GeneratedTokenNoIdTest"]["id"].generated);
    assert(!schema["GeneratedTokenNoIdTest"]["token"].key);
    assert(schema["IdNotFirstTest"].getKeyProperty().propertyName == "code");
    assert(!schema["IdNotFirstTest"]["id"].key);
}

unittest {
    
    // Checking generated metadata
    EntityMetaData schema = new SchemaInfoImpl!(User, Customer, AccountType, T1, TypeTest, Address, Role);
    
    //writeln("metadata test 1");
    assert(schema["TypeTest"].length==29);
    assert(schema.getEntityCount() == 7);
    assert(schema["User"]["name"].columnName == "name");
    assert(schema["User"][0].columnName == "id");
    assert(schema["User"][2].propertyName == "flags");
    assert(schema["User"]["id"].generated == true);
    assert(schema["User"]["id"].key == true);
    assert(schema["User"]["name"].key == false);
    assert(schema["Customer"]["id"].generated == true);
    assert(schema["Customer"]["id"].key == true);
    assert(schema["Customer"]["address"].embedded == true);
    assert(schema["Customer"]["address"].referencedEntity !is null);
    assert(schema["Customer"]["address"].referencedEntity["streetAddress"].columnName == "street_address");
    assert(schema["User"]["customer"].columnName !is null);

    assert(!schema["User"].embeddable); // test if @Embeddable is working
    assert(schema["Address"].embeddable); // test if @Embeddable is working
    assert(schema["Address"].length == 3); // test if @Transient is working

    assert(schema["Customer"]["users"].relation == RelationType.OneToMany);
    assert(schema["User"]["customer"].relation == RelationType.ManyToOne);
    assert(schema["User"]["roles"].relation == RelationType.ManyToMany);
    assert(schema["User"]["roles"].joinTable !is null);
    assert(schema["User"]["roles"].joinTable.tableName == "role_users");
    assert(schema["User"]["roles"].joinTable.column1 == "user_fk");
    assert(schema["User"]["roles"].joinTable.column2 == "role_fk");
    assert(schema["Role"]["users"].joinTable.tableName == "role_users");
    assert(schema["Role"]["users"].joinTable.column1 == "role_fk");
    assert(schema["Role"]["users"].joinTable.column2 == "user_fk");

    assert(schema["Customer"]["users"].collection);

    assert(schema["User"]["id"].readFunc !is null);

    assert(schema["User"]["comment"].length == 1024);
    static assert(isGetterFunction!(__traits(getMember, User, "getComment"), "getComment"));
    static assert(isGetterFunction!(__traits(getMember, T1, "getComment"), "getComment"));
    static assert(hasMemberAnnotation!(User, "getComment", Null));
    static assert(hasMemberAnnotation!(T1, "getComment", Null));
    static assert(!isMainMemberForProperty!(User, "comment"));
    static assert(isMainMemberForProperty!(User, "getComment"));
    static assert(isMainMemberForProperty!(Customer, "users"));

    assert(schema["T1"]["comment"].nullable);
    assert(schema["User"]["comment"].nullable);

    assert(schema["TypeTest"]["id"].key);
    assert(schema["TypeTest"]["id"].key);
    assert(!schema["TypeTest"]["string_field"].nullable);
    assert(schema["TypeTest"]["nullable_string_field"].nullable);
    assert(!schema["TypeTest"]["byte_field"].nullable);
    assert(!schema["TypeTest"]["short_field"].nullable);
    assert(!schema["TypeTest"]["int_field"].nullable);
    assert(!schema["TypeTest"]["long_field"].nullable);
    assert(!schema["TypeTest"]["ubyte_field"].nullable);
    assert(!schema["TypeTest"]["ushort_field"].nullable);
    assert(!schema["TypeTest"]["ulong_field"].nullable);
    assert(!schema["TypeTest"]["datetime_field"].nullable);
    assert(!schema["TypeTest"]["date_field"].nullable);
    assert(!schema["TypeTest"]["time_field"].nullable);
    assert(schema["TypeTest"]["nullable_byte_field"].nullable);
    assert(schema["TypeTest"]["nullable_short_field"].nullable);
    assert(schema["TypeTest"]["nullable_int_field"].nullable);
    assert(schema["TypeTest"]["nullable_long_field"].nullable);
    assert(schema["TypeTest"]["nullable_ubyte_field"].nullable);
    assert(schema["TypeTest"]["nullable_ushort_field"].nullable);
    assert(schema["TypeTest"]["nullable_ulong_field"].nullable);
    assert(schema["TypeTest"]["nullable_datetime_field"].nullable);
    assert(schema["TypeTest"]["nullable_date_field"].nullable);
    assert(schema["TypeTest"]["nullable_time_field"].nullable);
    assert(!schema["TypeTest"]["float_field"].nullable);
    assert(!schema["TypeTest"]["double_field"].nullable);
    assert(schema["TypeTest"]["nullable_float_field"].nullable);
    assert(schema["TypeTest"]["nullable_double_field"].nullable);
    assert(schema["TypeTest"]["byte_array_field"].nullable);
    assert(schema["TypeTest"]["ubyte_array_field"].nullable);

    auto e2 = schema.createEntity("User");
    assert(e2 !is null);
    User e2user = cast(User)e2;
    assert(e2user !is null);




    // TODO:
    //    e2user.customer = new Customer();
    //    e2user.customer.id = 25;
    //    e2user.customer.name = "cust25";
    //    Variant v = schema.getPropertyValue(e2user, "customer");
    //    assert(v.get!Customer().name == "cust25");
    //    e2user.customer = null;
    //    //assert(schema.getPropertyValue(e2user, "customer").to!Object is null); //Variant(cast(Customer)null));
    //    Customer c42 = new Customer();
    //    c42.id = 42;
    //    c42.name = "customer 42";
    //    schema.setPropertyValue(e2user, "customer", Variant(c42));
    //    assert(e2user.customer.id == 42);
    //    //assert(schema.getPropertyValue(e2user, "customer") == 42);
    
    Object e1 = schema.findEntity("User").createEntity();
    assert(e1 !is null);
    User e1user = cast(User)e1;
    assert(e1user !is null);
    e1user.id = 25;
    
    
    
}

unittest {
    if (DB_TESTS_ENABLED) {


        //writeln("metadata test 2");
        
        // Checking generated metadata
        EntityMetaData schema = new SchemaInfoImpl!(User, Customer, AccountType, T1, TypeTest, Address, Role, GeneratorTest, Person, MoreInfo, EvenMoreInfo);
        Dialect dialect = getUnitTestDialect();

        DBInfo db = new DBInfo(dialect, schema);
        string[] createTables = db.getCreateTableSQL();
//        foreach(t; createTables)
//            writeln(t);
        string[] createIndexes = db.getCreateIndexSQL();
//        foreach(t; createIndexes)
//            writeln(t);
        static if (SQLITE_TESTS_ENABLED) {
            // the SQLite dialect writes INTEGER and AUTOINCREMENT since #96
            assert(db["users"].getCreateTableSQL() == "CREATE TABLE users (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, flags INTEGER NULL, comment TEXT NULL, customer_fk INTEGER NULL)");
            assert(db["customers"].getCreateTableSQL() == "CREATE TABLE customers (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, zip TEXT NULL, city TEXT NULL, street_address TEXT NULL, account_type_fk INTEGER NULL)");
            assert(db["account_type"].getCreateTableSQL() == "CREATE TABLE account_type (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL)");
            assert(db["t1"].getCreateTableSQL() == "CREATE TABLE t1 (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, flags INTEGER NOT NULL, comment TEXT NULL)");
            assert(db["role"].getCreateTableSQL() == "CREATE TABLE role (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL)");
            assert(db["generator_test"].getCreateTableSQL() == "CREATE TABLE generator_test (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL)");
            assert(db["role_users"].getCreateTableSQL() == "CREATE TABLE role_users (role_fk INTEGER NOT NULL, user_fk INTEGER NOT NULL, PRIMARY KEY (role_fk, user_fk), UNIQUE (user_fk, role_fk))");
        }



        DataSource ds = getUnitTestDataSource();
        if (ds is null)
            return; // DB tests disabled
        SessionFactory factory = new SessionFactoryImpl(schema, dialect, ds);
        scope(exit) factory.close();
        db = factory.getDBMetaData();
        {
            Connection conn = ds.getConnection();
            scope(exit) conn.close();
            db.updateDBSchema(conn, true, true);
        }
        fillTestTables(); // after closing conn: the in-memory pool has one connection

        {
            Session sess = factory.openSession();
            scope(exit) sess.close();
            
            User u1 = sess.load!User(1);
            //writeln("Loaded value: " ~ u1.toString);
            assert(u1.id == 1);
            assert(u1.name == "user 1");
            assert(u1.customer.name == "customer 1");
            assert(u1.customer.accountType() !is null);
            assert(u1.customer.accountType().name == "Type1");
            Role[] u1roles = u1.roles;
            assert(u1roles.length == 2);
            
            User u2 = sess.load!User(2);
            assert(u2.name == "user 2");
            assert(u2.flags == 22); // NULL is loaded as 0 if property cannot hold nulls
            
            User u3 = sess.get!User(3);
            assert(u3.name == "user 3");
            assert(u3.flags == 0); // NULL is loaded as 0 if property cannot hold nulls
            assert(u3.getComment() !is null);
            assert(u3.customer.name == "customer 2");
            assert(u3.customer.accountType() is null);
            
            User u4 = new User();
            sess.load(u4, 4);
            assert(u4.name == "user 4");
            assert(u4.getComment() is null);
            
            User u5 = new User();
            u5.id = 5;
            sess.refresh(u5);
            assert(u5.name == "test user 5");
            //assert(u5.customer !is null);
            
            u5 = sess.load!User(5);
            assert(u5.name == "test user 5");
            assert(u5.customer !is null);
            assert(u5.customer.id == 3);
            assert(u5.customer.name == "customer 3");
            assert(u5.customer.accountType() !is null);
            assert(u5.customer.accountType().name == "Type2");
            
            User u6 = sess.load!User(6);
            assert(u6.name == "test user 6");
            assert(u6.customer is null);
            
            // 
            //writeln("loading customer 3");
            // testing @Embedded property
            Customer c3 = sess.load!Customer(3);
            assert(c3.address.zip is null);
            assert(c3.address.streetAddress == "Baker Street, 24");
            c3.address.streetAddress = "Baker Street, 24/2";
            c3.address.zip = "55555";
            
            User[] c3users = c3.users;
            //writeln("        ***      customer has " ~ to!string(c3users.length) ~ " users");
            assert(c3users.length == 2);
            assert(c3users[0].customer == c3);
            assert(c3users[1].customer == c3);
            
            //writeln("updating customer 3");
            sess.update(c3);
            Customer c3_reloaded = sess.load!Customer(3);
            assert(c3.address.streetAddress == "Baker Street, 24/2");
            assert(c3.address.zip == "55555");

        }
        {
            Session sess = factory.openSession();
            scope(exit) sess.close();

            
            // check Session.save() when id is filled
            Customer c4 = new Customer();
            c4.id = 4;
            c4.name = "Customer_4";
            sess.save(c4);
            
            Customer c4_check = sess.load!Customer(4);
            assert(c4.id == c4_check.id);
            assert(c4.name == c4_check.name);
            
            sess.remove(c4);
            
            c4 = sess.get!Customer(4);
            assert (c4 is null);
            
            Customer c5 = new Customer();
            c5.name = "Customer_5";
            sess.save(c5);
            
            // Testing generator function (uuid)
            GeneratorTest g1 = new GeneratorTest();
            g1.name = "row 1";
            assert(g1.id is null);
            sess.save(g1);
            assert(g1.id !is null);
            
            
            assertThrown!MappingException(sess.createQuery("SELECT id, name, blabla FROM User ORDER BY name"));
            assertThrown!QuerySyntaxException(sess.createQuery("SELECT id: name FROM User ORDER BY name"));
            
            // test multiple row query
            Query q = sess.createQuery("FROM User ORDER BY name");
            User[] list = q.list!User();
            assert(list.length == 6);
            assert(list[0].name == "test user 5");
            assert(list[1].name == "test user 6");
            assert(list[2].name == "user 1");
            //      writeln("Read " ~ to!string(list.length) ~ " rows from User");
            //      foreach(row; list) {
            //          writeln(row.toString());
            //      }
            Variant[][] rows = q.listRows();
            assert(rows.length == 6);
            //      foreach(row; rows) {
            //          writeln(row);
            //      }
            assertThrown!HibernatedException(q.uniqueResult!User());
            assertThrown!HibernatedException(q.uniqueRow());
            
        }
        {
            Session sess = factory.openSession();
            scope(exit) sess.close();

            // test single row select
            Query q = sess.createQuery("FROM User AS u WHERE id = :Id and (u.name like '%test%' or flags=44)");
            assertThrown!HibernatedException(q.list!User()); // cannot execute w/o all parameters set
            q.setParameter("Id", Variant(6));
            User[] list = q.list!User();
            assert(list.length == 1);
            assert(list[0].name == "test user 6");
            //      writeln("Read " ~ to!string(list.length) ~ " rows from User");
            //      foreach(row; list) {
            //          writeln(row.toString());
            //      }
            User uu = q.uniqueResult!User();
            assert(uu.name == "test user 6");
            Variant[] row = q.uniqueRow();
            assert(row[0] == 6L);
            assert(row[1] == "test user 6");
            
            // test empty SELECT result
            q.setParameter("Id", Variant(7));
            row = q.uniqueRow();
            assert(row is null);
            uu = q.uniqueResult!User();
            assert(uu is null);
            
            q = sess.createQuery("SELECT c.name, c.address.zip FROM Customer AS c WHERE id = :Id").setParameter("Id", Variant(1));
            row = q.uniqueRow();
            assert(row !is null);
            assert(row[0] == "customer 1"); // name
            assert(row[1] == "12345"); // address.zip


        }
        {
            // prepare data
            Session sess = factory.openSession();
            scope(exit) sess.close();

            Role r10 = new Role();
            r10.name = "role10";
            Role r11 = new Role();
            r11.name = "role11";
            Customer c10 = new Customer();
            c10.name = "Customer 10";
            User u10 = new User();
            u10.name = "Alex";
            u10.customer = c10;
            u10.roles = [r10, r11];
            sess.save(r10);
            sess.save(r11);
            sess.save(c10);
            sess.save(u10);
            assert(c10.id != 0);
            assert(u10.id != 0);
            assert(r10.id != 0);
            assert(r11.id != 0);
        }
        {
            // check data in separate session
            Session sess = factory.openSession();
            scope(exit) sess.close();
            User u10 = sess.createQuery("FROM User WHERE name=:Name").setParameter("Name", "Alex").uniqueResult!User();
            assert(u10.roles.length == 2);
            assert(u10.roles[0].name == "role10" || u10.roles.get()[0].name == "role11");
            assert(u10.roles[1].name == "role10" || u10.roles.get()[1].name == "role11");
            assert(u10.customer.name == "Customer 10");
            assert(u10.customer.users.length == 1);
            assert(u10.customer.users[0] == u10);
            assert(u10.roles[0].users.length == 1);
            assert(u10.roles[0].users[0] == u10);
            // removing one role from user
            u10.roles.get().remove(0);
            sess.update(u10);
        }
        {
            // check that only one role left
            Session sess = factory.openSession();
            scope(exit) sess.close();
            User u10 = sess.createQuery("FROM User WHERE name=:Name").setParameter("Name", "Alex").uniqueResult!User();
            assert(u10.roles.length == 1);
            assert(u10.roles[0].name == "role10" || u10.roles.get()[0].name == "role11");
            // remove user
            sess.remove(u10);
        }
        {
            // check that user is removed
            Session sess = factory.openSession();
            scope(exit) sess.close();
            User u10 = sess.createQuery("FROM User WHERE name=:Name").setParameter("Name", "Alex").uniqueResult!User();
            assert(u10 is null);
        }
    }
}


version (unittest) {
    // for testing of Embeddable
    @Embeddable 
    class EMName {
        string firstName;
        string lastName;
    }
    
    //@Entity 
    class EMUser {
        //@Id @Generated
        //@Column
        int id;
        
        // deduced as @Embedded automatically
        EMName userName;
    }
    
    // for testing of Embeddable
    //@Entity
    class Person {
        //@Id
        int id;
        
        // @Column @NotNull        
        string firstName;
        // @Column @NotNull        
        string lastName;
        
        @NotNull
        @OneToOne
        @JoinColumn("more_info_fk")
        MoreInfo moreInfo;
    }
    
    
    //@Entity
    @Table("person_info")
    class MoreInfo {
        //@Id @Generated
        int id;
        // @Column 
        long flags;
        @OneToOne("moreInfo")
        Person person;
        @OneToOne("personInfo")
        EvenMoreInfo evenMore;
    }
    
    //@Entity
    @Table("person_info2")
    class EvenMoreInfo {
        //@Id @Generated
        int id;
        //@Column 
        long flags;
        @OneToOne
        @JoinColumn("person_info_fk")
        MoreInfo personInfo;
    }
    
}


unittest {
    static assert(hasAnnotation!(EMName, Embeddable));
    static assert(isEmbeddedObjectMember!(EMUser, "userName"));
    static assert(!hasMemberAnnotation!(EMUser, "userName", OneToOne));
    static assert(getPropertyEmbeddedEntityName!(EMUser, "userName") == "EMName");
    static assert(getPropertyEmbeddedClassName!(EMUser, "userName") == "hibernated.tests.EMName");
    //pragma(msg, getEmbeddedPropertyDef!(EMUser, "userName")());
    
    // Checking generated metadata
    EntityMetaData schema = new SchemaInfoImpl!(EMName, EMUser);
    
    static assert(hasMemberAnnotation!(Person, "moreInfo", OneToOne));
    static assert(getPropertyReferencedEntityName!(Person, "moreInfo") == "MoreInfo");
    static assert(getPropertyReferencedClassName!(Person, "moreInfo") == "hibernated.tests.MoreInfo");
    //pragma(msg, getOneToOnePropertyDef!(Person, "moreInfo"));
    //pragma(msg, getOneToOnePropertyDef!(MoreInfo, "person"));
    //pragma(msg, "running getOneToOneReferencedPropertyName");
    //pragma(msg, getOneToOneReferencedPropertyName!(MoreInfo, "person"));
    static assert(getJoinColumnName!(Person, "moreInfo") == "more_info_fk");
    static assert(getOneToOneReferencedPropertyName!(MoreInfo, "person") == "moreInfo");
    static assert(getOneToOneReferencedPropertyName!(Person, "moreInfo") is null);
    
    //pragma(msg, "done getOneToOneReferencedPropertyName");
    
    // Checking generated metadata
    //EntityMetaData schema = new SchemaInfoImpl!(Person, MoreInfo);
    //  foreach(e; schema["Person"]) {
    //      writeln("property: " ~ e.propertyName);
    //  }
    schema = new SchemaInfoImpl!(hibernated.tests); //Person, MoreInfo, EvenMoreInfo, 
    
    {
        
        int[Variant] map0;
        map0[Variant(1)] = 3;
        assert(map0[Variant(1)] == 3);
        map0[Variant(1)]++;
        assert(map0[Variant(1)] == 4);
        
        //writeln("map test");
        PropertyLoadMap map = new PropertyLoadMap();
        Person ppp1 = new Person();
        Person ppp2 = new Person();
        Person ppp3 = new Person();
        //writeln("adding first");
        map.add(schema["Person"]["moreInfo"], Variant(1), ppp1);
        //writeln("adding second");
        auto prop1 = schema["Person"]["moreInfo"];
        auto prop2 = schema["Person"]["moreInfo"];
        map.add(prop1, Variant(2), ppp2);
        map.add(prop2, Variant(2), ppp3);
        map.add(prop2, Variant(2), ppp3);
        map.add(prop2, Variant(2), ppp3);
        map.add(prop2, Variant(2), ppp3);
        assert(prop1 == prop2);
        assert(prop1.opHash() == prop2.opHash());
        //writeln("checking length");
        assert(Variant(3) == Variant(3L));
        assert(map.length == 1);
        assert(map.map.length == 1);
        assert(map.keys.length == 1);
        assert(map.map.values.length == 1);
        //writeln("length of moreInfo is " ~ to!string(map[prop1].length));
        auto m = map[prop1];
        assert(m == map[prop2]);
        assert(m.map.length == 2);
        Variant v1 = 1;
        Variant v2 = 2;
        //writeln("length for id 1 " ~ to!string(m[Variant(1)].length));
        //writeln("length for id 2 " ~ to!string(m[Variant(2)].length));
        assert(m.length == 2);
        assert(m[Variant(1)].length == 1);
        assert(m[Variant(2)].length == 2);
    }
    
    if (DB_TESTS_ENABLED) {
        // uses the tables that the previous DB unittest created (updateDBSchema) and filled (fillTestTables),
        // in the same in-memory database
        
        //writeln("metadata test 2");
        
        // Checking generated metadata
        Dialect dialect = getUnitTestDialect();
        DataSource ds = getUnitTestDataSource();
        if (ds is null)
            return; // DB tests disabled
        SessionFactory factory = new SessionFactoryImpl(schema, dialect, ds);
        scope(exit) factory.close();
        {
            Session sess = factory.openSession();
            scope(exit) sess.close();

            auto p1 = sess.get!Person(1);
            assert(p1 !is null, "person 1 missing: this test needs the rows the previous DB unittest inserted");
            assert(p1.firstName == "Andrei");
            

            // all non-null oneToOne relations
            auto q = sess.createQuery("FROM Person WHERE id=:Id").setParameter("Id", Variant(1));
            Person p2 = q.uniqueResult!Person();
            assert(p2 !is null);
            assert(p2.firstName == "Andrei");
            assert(p2.moreInfo !is null);
            assert(p2.moreInfo.person !is null);
            assert(p2.moreInfo.person == p2);
            assert(p2.moreInfo.flags == 123);
            assert(p2.moreInfo.evenMore !is null);
            assert(p2.moreInfo.evenMore.flags == 1);
            assert(p2.moreInfo.evenMore.personInfo !is null);
            assert(p2.moreInfo.evenMore.personInfo == p2.moreInfo);


            // null oneToOne relation
            q = sess.createQuery("FROM Person WHERE id=:Id").setParameter("Id", Variant(3));
            p2 = q.uniqueResult!Person();
            assert(p2 !is null);
            assert(p2.firstName == "John");
            assert(p2.moreInfo !is null);
            assert(p2.moreInfo.person !is null);
            assert(p2.moreInfo.person == p2);
            assert(p2.moreInfo.flags == 345);
            assert(p2.moreInfo.evenMore is null);

        }
        
    }
}

unittest {
    // bool properties accept integers 0 and 1, which several drivers return for booleans (#124)
    import std.conv : ConvOverflowException;
    import std.exception : assertThrown;
    EntityMetaData schema = new SchemaInfoImpl!(BoolTest);
    auto info = schema["BoolTest"];
    auto e = new BoolTest();
    info.setPropertyValue(e, "flag", Variant(1L));
    assert(e.flag);
    info.setPropertyValue(e, "flag", Variant(0));
    assert(!e.flag);
    info.setPropertyValue(e, "flag", Variant(cast(ubyte) 1));
    assert(e.flag);
    info.setPropertyValue(e, "flag", Variant(false));
    assert(!e.flag);
    info.setPropertyValue(e, "flag", Variant(true));
    // out of range: the property stays unchanged
    assertThrown!ConvOverflowException(info.setPropertyValue(e, "flag", Variant(2)));
    assertThrown!ConvOverflowException(info.setPropertyValue(e, "flag", Variant(-1L)));
    assert(e.flag);
    info.setPropertyValue(e, "flag", Variant());
    assert(!e.flag); // NULL sets the default
}

unittest {
    // join-table statements bind the keys as parameters; HQL key literals write dates in ISO form (#122)
    import hibernated.dialects.mysqldialect : MySQLDialect;
    auto jt = new JoinTableInfo("role_users", "role_fk", "user_fk");
    Dialect d = new MySQLDialect();
    assert(jt.getOtherKeySelectSQL(d) == "SELECT user_fk FROM role_users WHERE role_fk=?");
    assert(jt.getInsertSQL(d, 2) == "INSERT INTO role_users(role_fk, user_fk) VALUES (?, ?), (?, ?)");
    assert(jt.getDeleteSQL(d, 3) == "DELETE FROM role_users WHERE role_fk=? AND user_fk IN (?, ?, ?)");
    assert(jt.getDeleteAllSQL(d) == "DELETE FROM role_users WHERE role_fk=?");

    assert(keyText(Variant(Date(2019, 9, 15))) == "2019-09-15");
    assert(keyText(Variant(DateTime(2019, 9, 15, 1, 2, 3))) == "2019-09-15 01:02:03");
    assert(keyText(Variant(TimeOfDay(1, 2, 3))) == "01:02:03");
    assert(keyText(Variant(cast(const) Date(2019, 9, 15))) == "2019-09-15");
    assert(keyText(Variant(cast(immutable) DateTime(2019, 9, 15, 1, 2, 3))) == "2019-09-15 01:02:03");
    assert(keyText(Variant(cast(const) TimeOfDay(1, 2, 3))) == "01:02:03");
    // ClickHouse reads a DateTime key back as a SysTime in the column timezone
    immutable plusOne = new immutable SimpleTimeZone(dur!"hours"(1));
    assert(keyText(Variant(SysTime(DateTime(2019, 9, 15, 1, 2, 3), plusOne))) == "2019-09-15 01:02:03");
    assert(keyText(Variant(5)) == keyText(Variant(5L)));
    // SQLite reads a date key back as text: updateRelations must see the same key
    assert(keyText(Variant(Date(2019, 9, 15))) == keyText(Variant("2019-09-15")));

    assert(createKeySQL(Variant(42L)) == "42");
    assert(createKeySQL(Variant("O'Brien")) == "'O''Brien'");
    assert(createKeySQL(Variant("C:\\dir\\")) == "'C:\\dir\\'"); // HQL: the dialect quotes the value again
    assert(createKeySQL(Variant(Date(2019, 9, 15))) == "'2019-09-15'");
    assert(createKeySQL(Variant(DateTime(2019, 9, 15, 1, 2, 3))) == "'2019-09-15 01:02:03'");
}

unittest {
    // transactions after errors (#135): rollback() ends the transaction also when it fails, and clears the
    // session cache; Session.close() rolls an active transaction back
    import std.exception : assertThrown, collectException;
    import ddbc.common : createConnection;
    EntityMetaData schema = new SchemaInfoImpl!(TxStateTest);
    DataSource ds = getUnitTestDataSource();
    if (ds is null)
        return; // DB tests disabled
    SessionFactory factory = new SessionFactoryImpl(schema, getUnitTestDialect(), ds);
    scope(exit) factory.close();
    {
        Connection conn = ds.getConnection();
        scope(exit) conn.close();
        factory.getDBMetaData().updateDBSchema(conn, true, true);
    }
    {
        Session sess = factory.openSession();
        scope(exit) sess.close();
        auto e = new TxStateTest();
        e.id = 3;
        e.name = "committed";
        auto t = sess.beginTransaction();
        sess.save(e);
        t.commit();

        // a change rolled back: the cached object must not keep it
        t = sess.beginTransaction();
        e.name = "rolled back";
        sess.update(e);
        t.rollback();
        auto loaded = sess.get!TxStateTest(3);
        assert(loaded !is null && loaded.name == "committed", "the session cache kept the rolled-back change");

        // a rollback that fails (here: a closed connection) still ends the transaction
        auto impl = cast(SessionImpl) sess;
        auto good = impl.conn;
        auto dead = createConnection("sqlite::memory:");
        dead.close();
        t = sess.beginTransaction();
        impl.conn = dead;
        assert(collectException(t.rollback()) !is null);
        impl.conn = good;
        assert(!t.isActive(), "a failed rollback left the transaction active");
        good.rollback(); // the real connection's transaction (begin turned auto-commit off on it)
        good.setAutoCommit(true);
        t = sess.beginTransaction(); // begin works again
        t.rollback();
    }
    {
        Session sess = factory.openSession();
        auto t = sess.beginTransaction();
        auto e = new TxStateTest();
        e.id = 4;
        e.name = "never committed";
        sess.save(e);
        sess.close(); // with the transaction active
        assert(!t.isActive(), "closing the session left its transaction active");
    }
    {
        Session sess = factory.openSession();
        scope(exit) sess.close();
        assert(sess.get!TxStateTest(4) is null, "closing the session committed its transaction");
    }
}
