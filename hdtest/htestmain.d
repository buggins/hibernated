module htestmain;

import std.stdio;
import std.string;
import std.conv;
import ddbc.drivers.sqliteddbc;
import hibernated.core;
import hibernated.dialects.sqlitedialect;
import std.traits;

// Annotations of entity classes
class User {
    long id;
    string name;
    int some_field_with_underscore;
    @ManyToMany // cannot be inferred, requires annotation
        LazyCollection!Role roles;
}

class Role {
    int id;
    string name;
    @ManyToMany // w/o this annotation will be OneToMany by convention
        LazyCollection!User users;
}

void testHibernate() {
    // setup DB connection
    SQLITEDriver driver = new SQLITEDriver();
    string[string] params;
    DataSource ds = new ConnectionPoolDataSourceImpl(driver, "zzz.db", params);

    // create metadata from annotations
    writeln("Creating schema from class list");
    EntityMetaData schema = new SchemaInfoImpl!(User, Role);
    writeln("Creating schema from module list");
    EntityMetaData schema2 = new SchemaInfoImpl!(htestmain);


    writeln("Creating session factory");
    // create session factory
    Dialect dialect = new SQLiteDialect();
    SessionFactory factory = new SessionFactoryImpl(schema, dialect, ds);
    scope(exit) factory.close();

    writeln("Creating DB schema");
    DBInfo db = factory.getDBMetaData();
    {
        Connection conn = ds.getConnection();
        scope(exit) conn.close();
        db.updateDBSchema(conn, true, true);
    }


    // create session
    Session sess = factory.openSession();
    scope(exit) sess.close();

    // use session to access DB

    writeln("Querying empty DB");
    Query q = sess.createQuery("FROM User ORDER BY name");
    User[] list = q.list!User();
    writeln("Result size is " ~ to!string(list.length));

    // create sample data
    writeln("Creating sample schema");
    Role r10 = new Role();
    r10.name = "role10";
    Role r11 = new Role();
    r11.name = "role11";
    User u10 = new User();
    u10.name = "Alex";
    u10.roles = [r10, r11];
    writeln("Saving r10");
    sess.save(r10);
    writeln("Saving r11");
    sess.save(r11);
    writeln("Saving u10");
    sess.save(u10);

    writeln("Loading User");
    // load and check data
    User u11 = sess.createQuery("FROM User WHERE name=:Name and some_field_with_underscore != 42").setParameter("Name", "Alex").uniqueResult!User();
    writeln("Checking User");
    assert(u11.roles.length == 2);
    assert(u11.roles[0].name == "role10" || u11.roles.get()[0].name == "role11");
    assert(u11.roles[1].name == "role10" || u11.roles.get()[1].name == "role11");
    assert(u11.roles[0].users.length == 1);
    assert(u11.roles[0].users[0] == u10);

    writeln("Removing User");
    // remove reference
    std.algorithm.remove(u11.roles.get(), 0);
    sess.update(u11);

    // remove entity
    sess.remove(u11);
}

void main()
{
    testHibernate();
    writeln("Press any key");
    readln();

}