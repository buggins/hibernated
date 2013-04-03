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

import std.conv;
import std.stdio;
import std.datetime;
import std.typecons;
import std.exception;
import std.variant;

import hibernated.core;

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
        @ManyToOne
        @JoinColumn("customer_fk")
        Customer customer;
        
        @ManyToMany
        LazyCollection!Role roles;
        
        override string toString() {
            return "id=" ~ to!string(id) ~ ", name=" ~ name ~ ", flags=" ~ to!string(flags) ~ ", comment=" ~ comment ~ ", customerId=" ~ (customer is null ? "NULL" : customer.toString());
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
        @Embedded
        Address address;
        
        @ManyToOne
        @JoinColumn("account_type_fk")
        Lazy!AccountType accountType;
        
        //        @OneToMany("customer")
        //        LazyCollection!User users;
        
        @OneToMany("customer")
        User[] users;
        
        this() {
            address = new Address();
        }
        override string toString() {
            return "id=" ~ to!string(id) ~ ", name=" ~ name ~ ", address=" ~ address.toString();
        }
    }
    
    @Embeddable
    class Address {
        @Column
        string zip;
        @Column
        string city;
        @Column
        string streetAddress;
        override string toString() {
            return " zip=" ~ zip ~ ", city=" ~ city ~ ", streetAddress=" ~ streetAddress;
        }
    }
    
    @Entity
    class AccountType {
        @Generated
        int id;
        @Column
        string name;
    }
    
    @Entity 
    class Role {
        @Generated
        int id;
        @Column
        string name;
        @ManyToMany
        LazyCollection!User users;
    }
    
    @Entity
    @Table("t1")
    class T1 {
        @Id @Generated
        @Column
        int id;
        
        @Column
        @NotNull
        @UniqueKey
        string name;
        
        // property column
        private long _flags;
        @Column
        @property long flags() { return _flags; }
        @property void flags(long v) { _flags = v; }
        
        // getter/setter property
        string comment;
        @Column
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
        @Column
        string name;
    }
    
    @Entity
    static class TypeTest {
        @Generated
        int id;
        
        @Column
        string string_field;
        
        @Column
        byte byte_field;
        @Column
        short short_field;
        @Column
        int int_field;
        @Column
        long long_field;
        @Column
        ubyte ubyte_field;
        @Column
        ushort ushort_field;
        @Column
        ulong ulong_field;
        @Column
        DateTime datetime_field;
        @Column
        Date date_field;
        @Column
        TimeOfDay time_field;
        
        @Column
        Nullable!byte nullable_byte_field;
        @Column
        Nullable!short nullable_short_field;
        @Column
        Nullable!int nullable_int_field;
        @Column
        Nullable!long nullable_long_field;
        @Column
        Nullable!ubyte nullable_ubyte_field;
        @Column
        Nullable!ushort nullable_ushort_field;
        @Column
        Nullable!ulong nullable_ulong_field;
        @Column
        Nullable!DateTime nullable_datetime_field;
        @Column
        Nullable!Date nullable_date_field;
        @Column
        Nullable!TimeOfDay nullable_time_field;
        
        @Column
        float float_field;
        @Column
        double double_field;
        @Column
        Nullable!float nullable_float_field;
        @Column
        Nullable!double nullable_double_field;
        
        @Column
        byte[] byte_array_field;
        @Column
        ubyte[] ubyte_array_field;
    }
    
    import ddbc.drivers.mysqlddbc;
    import ddbc.common;
    
    
    string[] UNIT_TEST_DROP_TABLES_SCRIPT = 
        [
         "DROP TABLE IF EXISTS role_users",
         "DROP TABLE IF EXISTS account_type",
         "DROP TABLE IF EXISTS users",
         "DROP TABLE IF EXISTS customers",
         "DROP TABLE IF EXISTS person",
         "DROP TABLE IF EXISTS person_info",
         "DROP TABLE IF EXISTS person_info2",
         "DROP TABLE IF EXISTS role",
         "DROP TABLE IF EXISTS generator_test",
         ];
    string[] UNIT_TEST_CREATE_TABLES_SCRIPT = 
        [
         "CREATE TABLE IF NOT EXISTS role (id INT NOT NULL PRIMARY KEY AUTO_INCREMENT, name VARCHAR(255) NOT NULL)",
         "CREATE TABLE IF NOT EXISTS account_type (id INT NOT NULL PRIMARY KEY AUTO_INCREMENT, name VARCHAR(255) NOT NULL)",
         "CREATE TABLE IF NOT EXISTS users (id BIGINT NOT NULL PRIMARY KEY AUTO_INCREMENT, name VARCHAR(255) NOT NULL, flags INT, comment TEXT, customer_fk BIGINT NULL)",
         "CREATE TABLE IF NOT EXISTS customers (id BIGINT NOT NULL PRIMARY KEY AUTO_INCREMENT, name VARCHAR(255) NOT NULL, zip varchar(20), city varchar(100), street_address varchar(255), account_type_fk int)",
         "CREATE TABLE IF NOT EXISTS person_info (id int not null primary key AUTO_INCREMENT, flags bigint)",
         "CREATE TABLE IF NOT EXISTS person (id int not null primary key AUTO_INCREMENT, first_name varchar(255) not null, last_name varchar(255) not null, more_info_fk int)",
         "CREATE TABLE IF NOT EXISTS person_info2 (id int not null primary key AUTO_INCREMENT, flags bigint, person_info_fk int)",
         "CREATE TABLE IF NOT EXISTS role_users (role_fk int not null, user_fk int not null, primary key (role_fk, user_fk), unique index(user_fk, role_fk))",
         "CREATE TABLE IF NOT EXISTS generator_test (id varchar(64) not null primary key, name varchar(255) not null)",
         
         "INSERT INTO role SET id=1, name='admin'",
         "INSERT INTO role SET id=2, name='viewer'",
         "INSERT INTO role SET id=3, name='editor'",
         "INSERT INTO account_type SET id=1, name='Type1'",
         "INSERT INTO account_type SET id=2, name='Type2'",
         "INSERT INTO customers SET id=1, name='customer 1', zip='12345', account_type_fk=1",
         "INSERT INTO customers SET id=2, name='customer 2', zip='54321'",
         "INSERT INTO customers SET id=3, name='customer 3', street_address='Baker Street, 24', account_type_fk=2",
         "INSERT INTO users SET id=1, name='user 1', flags=11,   comment='comments for user 1', customer_fk=1",
         "INSERT INTO users SET id=2, name='user 2', flags=22,   comment='this user belongs to customer 1', customer_fk=1",
         "INSERT INTO users SET id=3, name='user 3', flags=NULL, comment='this user belongs to customer 2', customer_fk=2",
         "INSERT INTO users SET id=4, name='user 4', flags=44,   comment=NULL, customer_fk=3",
         "INSERT INTO users SET id=5, name='test user 5', flags=55,   comment='this user belongs to customer 3, too', customer_fk=3",
         "INSERT INTO users SET id=6, name='test user 6', flags=66,   comment='for checking of Nullable!long reading', customer_fk=null",
         "INSERT INTO person_info SET id=3, flags=123",
         "INSERT INTO person_info SET id=4, flags=234",
         "INSERT INTO person_info SET id=5, flags=345",
         "INSERT INTO person_info2 SET id=10, flags=1, person_info_fk=3",
         "INSERT INTO person_info2 SET id=11, flags=2, person_info_fk=4",
         "INSERT INTO person SET id=1, first_name='Andrei', last_name='Alexandrescu', more_info_fk=3",
         "INSERT INTO person SET id=2, first_name='Walter', last_name='Bright', more_info_fk=4",
         "INSERT INTO person SET id=3, first_name='John', last_name='Smith', more_info_fk=5",
         "INSERT INTO role_users SET role_fk=1, user_fk=1",
         "INSERT INTO role_users SET role_fk=2, user_fk=1",
         "INSERT INTO role_users SET role_fk=2, user_fk=2",
         "INSERT INTO role_users SET role_fk=2, user_fk=3",
         "INSERT INTO role_users SET role_fk=3, user_fk=2",
         "INSERT INTO role_users SET role_fk=3, user_fk=3",
         "INSERT INTO role_users SET role_fk=3, user_fk=5",
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
    EntityMetaData schema = new SchemaInfoImpl!(User, Customer, AccountType, T1, TypeTest, Address, Role);
    
    writeln("metadata test 1");
    
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
    
    assert(schema["User"]["id"].readFunc !is null);
    
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
    if (MYSQL_TESTS_ENABLED) {
        recreateTestSchema();

        import hibernated.dialects.mysqldialect;

        writeln("metadata test 2");
        
        // Checking generated metadata
        EntityMetaData schema = new SchemaInfoImpl!(User, Customer, AccountType, T1, TypeTest, Address, Role, GeneratorTest);
        Dialect dialect = new MySQLDialect();
        DataSource ds = createUnitTestMySQLDataSource();
        SessionFactory factory = new SessionFactoryImpl(schema, dialect, ds);
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
        writeln("        ***      customer has " ~ to!string(c3users.length) ~ " users");
        assert(c3users.length == 2);
        assert(c3users[0].customer == c3);
        assert(c3users[1].customer == c3);
        
        //writeln("updating customer 3");
        sess.update(c3);
        Customer c3_reloaded = sess.load!Customer(3);
        assert(c3.address.streetAddress == "Baker Street, 24/2");
        assert(c3.address.zip == "55555");
        
        
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
        
        // test single row select
        q = sess.createQuery("FROM User AS u WHERE id = :Id and (u.name like '%test%' or flags=44)");
        assertThrown!HibernatedException(q.list!User()); // cannot execute w/o all parameters set
        q.setParameter("Id", Variant(6));
        list = q.list!User();
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
        
        writeln("Unit tests");
    }
}


version (unittest) {
    // for testing of Embeddable
    @Embeddable 
    class EMName {
        @Column
        string firstName;
        @Column
        string lastName;
    }
    
    @Entity 
    class EMUser {
        @Id @Generated
        @Column
        int id;
        
        @Embedded 
        EMName userName;
    }
    
    // for testing of Embeddable
    @Entity("Person")
    class Person {
        @Id
        int id;
        
        @Column @NotNull
        string firstName;
        
        @Column @NotNull
        string lastName;
        
        @OneToOne @NotNull
        @JoinColumn("more_info_fk")
        MoreInfo moreInfo;
    }
    
    
    @Entity("More")
    @Table("person_info")
    class MoreInfo {
        @Id @Generated
        int id;
        @Column 
        long flags;
        @OneToOne("moreInfo")
        Person person;
        @OneToOne("personInfo")
        EvenMoreInfo evenMore;
    }
    
    @Entity("EvenMore")
    @Table("person_info2")
    class EvenMoreInfo {
        @Id @Generated
        int id;
        @Column 
        long flags;
        @OneToOne
        @JoinColumn("person_info_fk")
        MoreInfo personInfo;
    }
    
}


unittest {
    static assert(hasAnnotation!(EMName, Embeddable));
    static assert(hasMemberAnnotation!(EMUser, "userName", Embedded));
    static assert(!hasMemberAnnotation!(EMUser, "userName", OneToOne));
    static assert(getPropertyEmbeddedEntityName!(EMUser, "userName") == "EMName");
    static assert(getPropertyEmbeddedClassName!(EMUser, "userName") == "hibernated.tests.EMName");
    //pragma(msg, getEmbeddedPropertyDef!(EMUser, "userName")());
    
    // Checking generated metadata
    EntityMetaData schema = new SchemaInfoImpl!(EMName, EMUser);
    
    static assert(hasMemberAnnotation!(Person, "moreInfo", OneToOne));
    static assert(getPropertyReferencedEntityName!(Person, "moreInfo") == "More");
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
    schema = new SchemaInfoImpl!(Person, MoreInfo, EvenMoreInfo);
    
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
    
    if (MYSQL_TESTS_ENABLED) {
        //recreateTestSchema();
        
        //writeln("metadata test 2");
        import hibernated.dialects.mysqldialect;
        
        // Checking generated metadata
        Dialect dialect = new MySQLDialect();
        DataSource ds = createUnitTestMySQLDataSource();
        SessionFactory factory = new SessionFactoryImpl(schema, dialect, ds);
        Session sess = factory.openSession();
        scope(exit) sess.close();
        
        auto p1 = sess.get!Person(1);
        assert(p1.firstName == "Andrei");
        
        // all non-null oneToOne relations
        auto q = sess.createQuery("FROM Person WHERE id=:Id").setParameter("Id", Variant(1));
        Person p2 = q.uniqueResult!Person();
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
        assert(p2.firstName == "John");
        assert(p2.moreInfo !is null);
        assert(p2.moreInfo.person !is null);
        assert(p2.moreInfo.person == p2);
        assert(p2.moreInfo.flags == 345);
        assert(p2.moreInfo.evenMore is null);
        
    }
}


