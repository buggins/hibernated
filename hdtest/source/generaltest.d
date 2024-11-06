module generaltest;

import std.typecons;
import std.stdio;
import std.format;
import std.conv;

import hibernated.core;

import testrunner : BeforeClass, Test, AfterClass, runTests;
import hibernatetest : HibernateTest;

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
    return format("{id: %s, name: %s, roles: %s, group: %s}",
        id, name, roles, group);
  }
}

class Role {
  int id;
  string name;
  @ManyToMany // w/o this annotation will be OneToMany by convention
  LazyCollection!User users;

  override string toString() {
    return format("{id: %s, name: %s}", id, name);
  }
}

class Address {
  @Generated @Id int addressId;
  User user;
  string street;
  string town;
  string country;

  override string toString() {
    return format("{id: %s, user: %s, street: %s, town: %s, country: %s}", addressId, user, street, town, country);
  }
}

class Asset {
  @Generated @Id int id;
  User user;
  string name;

  override string toString() {
    return format("{id: %s, name: %s}", id, name);
  }
}

@Entity
class MyGroup {
  long id;
  string name;
  @OneToMany
  LazyCollection!User users;

  override string toString() {
    return format("{id: %s, name: %s}", id, name);
  }
}

class GeneralTest : HibernateTest {
  override
  EntityMetaData buildSchema() {
    return new SchemaInfoImpl!(User, Role, Address, Asset, MyGroup);
  }

  @Test("session_close")
  void sessionCloseTest() {
    assert((cast(SessionFactoryImpl) sessionFactory).activeSessions.length == 0);
    Session sess = sessionFactory.openSession();
    assert((cast(SessionFactoryImpl) sessionFactory).activeSessions.length == 1);
    sess.close();
    assert((cast(SessionFactoryImpl) sessionFactory).activeSessions.length == 0);
  }

  @Test("general test")
  void generalTest() {
    // create session
    Session sess = sessionFactory.openSession();
    scope(exit) sess.close();

    // use session to access DB

    writeln("Querying empty DB");
    Query q = sess.createQuery("FROM User ORDER BY name");
    User[] list = q.list!User();
    writeln("Result size is " ~ to!string(list.length));
    assert(list.length == 0);

    // create sample data
    writeln("Creating sample schema");
    MyGroup grp1 = new MyGroup();
    grp1.name = "Group-1";
    MyGroup grp2 = new MyGroup();
    grp2.name = "Group-2";
    MyGroup grp3 = new MyGroup();
    grp3.name = "Group-3";

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

    {
      writeln("Saving User u10: " ~ u10.name ~ "...");
      long id = sess.save(u10).get!long;
      assert(id > 0L);
      writeln("\tuser saved with id: " ~ to!string(id));
    }

    {
      writeln("Saving User u12: " ~ u12.name ~ "...");
      long id = sess.save(u12).get!long;
      assert(id > 0L);
      writeln("\tuser saved with id: " ~ to!string(id));
    }

    {
      writeln("Saving User u13: " ~ u13.name ~ "...");
      long id = sess.save(u13).get!long;
      assert(id > 0L);
      writeln("\tuser saved with id: " ~ to!string(id));
    }

    writeln("Querying User by name 'Alex'...");
    // load and check data
    auto qresult = sess.createQuery("FROM User WHERE name=:Name and some_field_with_underscore != 42").setParameter("Name", "Alex");
    writefln( "\tquery result: %s", qresult.listRows() );
    User u11 = qresult.uniqueResult!User();
    writefln("\tChecking fields for User 11 : %s", u11);
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

    {
      writeln("Updating User u10 name (from Alex to Alexander)...");
      u10.name = "Alexander";
      sess.update(u10);

      User u = sess.createQuery("FROM User WHERE id=:uid")
          .setParameter("uid", u10.id)
          .uniqueResult!User();
      assert(u.id == u10.id);
      assert(u.name == "Alexander");
    }

    // remove reference
    //std.algorithm.remove(u11.roles.get(), 0);
    //sess.update(u11);

    {
      auto allUsers = sess.createQuery("FROM User").list!User();
      assert(allUsers.length == 3); // Should be 3 user nows
    }
    writeln("Removing User u11");
    sess.remove(u11);

    {
      auto allUsers = sess.createQuery("FROM User").list!User();
      assert(allUsers.length == 2); // Should only be 2 users now
    }
  }

  @Test("quote escape test")
  void quoteEscapeTest() {
      Session sess = sessionFactory.openSession();
      scope(exit) sess.close();

      auto a1 = new Asset();
      a1.name = "Bucky O'Hare";
      int id = sess.save(a1).get!int;

      auto query = sess.createQuery("FROM Asset WHERE name=:Name").setParameter("Name", "Bucky O'Hare");
      writeln("FLOOB: query results", query.listRows());
  }
}

