module htestmain;

import std.algorithm;
import std.stdio;
import std.string;
import std.conv;
import std.getopt;
import hibernated.core;
import std.traits;

// Annotations of entity classes
@Table( "gebruiker" )
class User {
    long id;
    string name;
    int some_field_with_underscore;
    @ManyToMany // cannot be inferred, requires annotation
    LazyCollection!Role roles;
    //@ManyToOne
    MyGroup group;

    @OneToMany
    Address[] addresses;

    Asset[] assets;

    override string toString() {
        return format("{id:%s, name:%s, roles:%s, group:%s}", id, name, roles, group);
    }
}

class Role {
    int id;
    string name;
    @ManyToMany // w/o this annotation will be OneToMany by convention
    LazyCollection!User users;

    override string toString() {
        return format("{id:%s, name:%s}", id, name);
    }
}

class Address {
    @Generated @Id int id;
    User user;
    string street;
    string town;
    string country;

    override string toString() {
        return format("{id:%s, user:%s, street:%s, town:%s, country:%s}", id, user, street, town, country);
    }
}

class Asset {
    @Generated @Id int id;
    User user;
    string name;
}

@Entity
class MyGroup {
    long id;
    string name;
    @OneToMany
    LazyCollection!User users;

    override string toString() {
        return format("{id:%s, name:%s}", id, name);
    }
}

void testHibernate(immutable string host, immutable ushort port, immutable string dbName, immutable string dbUser, immutable string dbPass, immutable string driver) {

    // setup DB connection
    version( USE_SQLITE )
    {
        import ddbc.drivers.sqliteddbc;
        string[string] params;
        DataSource ds = new ConnectionPoolDataSourceImpl(new SQLITEDriver(), "zzz.db", params);
        Dialect dialect = new SQLiteDialect();
    }
    else version( USE_MYSQL )
    {
        import ddbc.drivers.mysqlddbc;
        immutable string url = MySQLDriver.generateUrl(host, port, dbName);
        string[string] params = MySQLDriver.setUserAndPassword(dbUser, dbPass);
        DataSource ds = new ConnectionPoolDataSourceImpl(new MySQLDriver(), url, params);
        Dialect dialect = new MySQLDialect();
    }
    else version( USE_PGSQL )
    {
        import ddbc.drivers.pgsqlddbc;
        immutable string url = PGSQLDriver.generateUrl(host, port, dbName); // PGSQLDriver.generateUrl( "/tmp", 5432, "testdb" );
        string[string] params;
        params["user"] = dbUser;
        params["password"] = dbPass;
        params["ssl"] = "true";
        
        DataSource ds = new ConnectionPoolDataSourceImpl(new PGSQLDriver(), url, params);
        Dialect dialect = new PGSQLDialect(); // should be called PostgreSQLDialect
    }
    else version( USE_TSQL )
    {
        // T-SQL is SQL Server
        import ddbc.drivers.odbcddbc;
        string[string] params = ODBCDriver.setUserAndPassword(par.user, par.password);
		params["driver"] = par.odbcdriver;
        immutable string url = ODBCDriver.generateUrl(par.host, par.port, params);

        DataSource ds = new ConnectionPoolDataSourceImpl(new ODBCDriver(), url, params);
        Dialect dialect = new SQLServerDialect();
    }
    else version( USE_PLSQL )
    {
        // PL/SQL is Oracle
        import ddbc.drivers.odbcddbc;
        string[string] params = ODBCDriver.setUserAndPassword(par.user, par.password);
		params["driver"] = par.odbcdriver;
        immutable string url = ODBCDriver.generateUrl(par.host, par.port, params);

        DataSource ds = new ConnectionPoolDataSourceImpl(new ODBCDriver(), url, params);
        Dialect dialect = new OracleDialect();
    }

    // create metadata from annotations
    writeln("Creating schema from class list");
    EntityMetaData schema = new SchemaInfoImpl!(User, Role, Address, Asset, MyGroup);
    //writeln("Creating schema from module list");
    //EntityMetaData schema2 = new SchemaInfoImpl!(htestmain);


    writeln("Creating session factory");
    // create session factory
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
    MyGroup grp1 = new MyGroup();
    grp1.name = "Group-1";
    MyGroup grp2 = new MyGroup();
    grp2.name = "Group-2";
    MyGroup grp3 = new MyGroup();
    grp3.name = "Group-3";
    //
    Role r10 = new Role();
    r10.name = "role10";
    Role r11 = new Role();
    r11.name = "role11";

    // create a user called Alex with an address and an asset
    User u10 = new User();
    u10.name = "Alex";
    u10.roles = [r10, r11];
    u10.group = grp3;
    auto address = new Address();
    address.street = "Some Street";
    address.town = "Big Town";
    address.country = "Alaska";
    address.user = u10;
    writefln("Saving Address: %s", address);
    sess.save(address);

    u10.addresses = [address];
    auto asset = new Asset();
    asset.name = "Something Precious";
    asset.user = u10;
    writefln("Saving Asset: %s", asset);
    sess.save(asset);
    u10.assets = [asset];

    User u12 = new User();
    u12.name = "Arjan";
    u12.roles = [r10, r11];
    u12.group = grp2;

    User u13 = new User();
    u13.name = "Wessel";
    u13.roles = [r10, r11];
    u13.group = grp2;

    writeln("saving group 1-2-3" );
    sess.save( grp1 );
    sess.save( grp2 );
    sess.save( grp3 );

    writeln("Saving Role r10: " ~ r10.name);
    sess.save(r10);

    writeln("Saving Role r11: " ~ r11.name);
    sess.save(r11);

    writeln("Saving User u10: " ~ u10.name);
    sess.save(u10);

    writeln("Saving User u12: " ~ u12.name);
    sess.save(u12);

    writeln("Saving User u13: " ~ u13.name);
    sess.save(u13);

    writeln("Loading User");
    // load and check data
    auto qresult = sess.createQuery("FROM User WHERE name=:Name and some_field_with_underscore != 42").setParameter("Name", "Alex");
    writefln( "query result: %s", qresult.listRows() );
    User u11 = qresult.uniqueResult!User();
    //User u11 = sess.createQuery("FROM User WHERE name=:Name and some_field_with_underscore != 42").setParameter("Name", "Alex").uniqueResult!User();
    writefln("Checking User 11 : %s", u11);
    assert(u11.roles.length == 2);
    assert(u11.roles[0].name == "role10" || u11.roles.get()[0].name == "role11");
    assert(u11.roles[1].name == "role10" || u11.roles.get()[1].name == "role11");
    assert(u11.roles[0].users.length == 3);
    assert(u11.roles[0].users[0] == u10);

    assert(u11.addresses.length == 1);
    assert(u11.addresses[0].street == "Some Street");
    assert(u11.addresses[0].town == "Big Town");
    assert(u11.addresses[0].country == "Alaska");

    assert(u11.assets.length == 1);
    assert(u11.assets[0].name == "Something Precious");

    // selecting all from address table should return a row that joins to the user table
    auto allAddresses = sess.createQuery("FROM Address").list!Address();
    assert(allAddresses.length == 1);
    writefln("Found address : %s", allAddresses[0]);
    assert(allAddresses[0].street == "Some Street");
    assert(allAddresses[0].user == u11);

    // selecting all from asset table should return a row that joins to the user table
    auto allAssets = sess.createQuery("FROM Asset").list!Asset();
    assert(allAssets.length == 1);
    writefln("Found asset : %s", allAssets[0]);
    assert(allAssets[0].name == "Something Precious");
    assert(allAssets[0].user == u11);

    // now test something else
    writeln("Test retrieving users by group... (ManyToOne relationship)");
    auto qUsersByGroup = sess.createQuery("FROM User WHERE group=:group_id").setParameter("group_id", grp2.id);
    User[] usersByGroup = qUsersByGroup.list!User();
    assert(usersByGroup.length == 2); // user 2 and user 2

    //writeln("Removing User");
    // remove reference
    //std.algorithm.remove(u11.roles.get(), 0);
    //sess.update(u11);

    // remove entity
    //sess.remove(u11);
}

struct ConnectionParams
{
    string host;
	ushort port;
    string database;
	string user;
	string pass;
    string driver;
}

int main(string[] args)
{
    ConnectionParams par;
    string URI;

    try
	{
		getopt(args, "host",&par.host, "port",&par.port, "database",&par.database, "user",&par.user, "password",&par.pass, "driver",&par.driver);
	}
	catch (GetOptException)
	{
		stderr.writefln("Could not parse args");
		return 1;
	}
    testHibernate(par.host, par.port, par.database, par.user, par.pass, par.driver);

    return 0;
}
