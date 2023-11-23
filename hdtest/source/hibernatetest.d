module hibernatetest;

import std.stdio;

import hibernated.core;

import testrunner : Test, BeforeClass, AfterClass;

/**
 * Generic parameters to connect to a database, independent of the driver.
 */
struct ConnectionParams {
  string host;
	ushort port;
  string database;
	string user;
	string pass;
}

/**
 * A base-class for most hibernate tests. It takes care of setting up and tearing down a connection
 * to a database using the appropriate driver and connection parameters. Tests annotated with
 * `@Test` can simply use a session factory to test hibernate queries.
 */
abstract class HibernateTest {
  ConnectionParams connectionParams;
  SessionFactory sessionFactory;

  EntityMetaData buildSchema();

  Dialect buildDialect() {
    version (USE_SQLITE) {
      Dialect dialect = new SQLiteDialect();
    } else version (USE_MYSQL) {
      Dialect dialect = new MySQLDialect();
    } else version (USE_PGSQL) {
      Dialect dialect = new PGSQLDialect();
    }
    return dialect;
  }
  DataSource buildDataSource(ConnectionParams connectionParams) {
    // setup DB connection
    version( USE_SQLITE )
    {
        import ddbc.drivers.sqliteddbc;
        string[string] params;
        DataSource ds = new ConnectionPoolDataSourceImpl(new SQLITEDriver(), "zzz.db", params);
    }
    else version( USE_MYSQL )
    {
        import ddbc.drivers.mysqlddbc;
        immutable string url = MySQLDriver.generateUrl(host, port, dbName);
        string[string] params = MySQLDriver.setUserAndPassword(
            connectionParams.user, connectionParams.pass);
        DataSource ds = new ConnectionPoolDataSourceImpl(new MySQLDriver(), url, params);
    }
    else version( USE_PGSQL )
    {
        import ddbc.drivers.pgsqlddbc;
        immutable string url = PGSQLDriver.generateUrl(
            connectionParams.host, connectionParams.port, connectionParams.database); // PGSQLDriver.generateUrl( "/tmp", 5432, "testdb" );
        string[string] params;
        params["user"] = connectionParams.user;
        params["password"] = connectionParasm.pass;
        params["ssl"] = "true";

        DataSource ds = new ConnectionPoolDataSourceImpl(new PGSQLDriver(), url, params);
    }
    return ds;
  }

  SessionFactory buildSessionFactory() {
    DataSource ds = buildDataSource(connectionParams);
    SessionFactory factory = new SessionFactoryImpl(buildSchema(), buildDialect(), ds);

    writeln("Creating DB Schema");
    DBInfo db = factory.getDBMetaData();
    {
      Connection conn = ds.getConnection();
      scope(exit) conn.close();
      db.updateDBSchema(conn, true, true);
    }
    return factory;
  }

  void setConnectionParams(ConnectionParams connectionParams) {
    this.connectionParams = connectionParams;
  }

  @BeforeClass
  void setup() {
    this.sessionFactory = buildSessionFactory();
  }

  @AfterClass
  void teardown() {
    this.sessionFactory.close();
  }
}
