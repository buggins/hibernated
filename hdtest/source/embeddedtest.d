module embeddedtest;

import hibernated.core;

import testrunner : BeforeClass, Test, AfterClass, runTests;
import hibernatetest : HibernateTest;

@Embeddable
class Address {
  string street;
  string city;
}

class Customer {
  @Id @Generated
  long cid;

  string name;

  Address shippingAddress;

  @Embedded("billing")
  Address billingAddress;
}

class EmbeddedTest : HibernateTest {
  override
  EntityMetaData buildSchema() {
    return new SchemaInfoImpl!(Customer, Address);
  }

  @Test("embedded.creation")
  void creationTest() {
    Session sess = sessionFactory.openSession();
    scope(exit) sess.close();

    Customer c1 = new Customer();
    c1.name = "Kickflip McOllie";
    c1.shippingAddress = new Address();
    c1.shippingAddress.street = "1337 Rad Street";
    c1.shippingAddress.city = "Awesomeville";
    c1.billingAddress = new Address();
    c1.billingAddress.street = "101001 Robotface";
    c1.billingAddress.city = "Lametown";

    long c1Id = sess.save(c1).get!long;
    assert(c1Id > 0);
  }

  @Test("embedded.read")
  void readTest() {
    Session sess = sessionFactory.openSession();
    scope(exit) sess.close();

    auto r1 = sess.createQuery("FROM Customer WHERE shippingAddress.city = :City")
        .setParameter("City", "Awesomeville");
    Customer c1 = r1.uniqueResult!Customer();
    assert(c1 !is null);
    assert(c1.shippingAddress.street == "1337 Rad Street");

    auto r2 = sess.createQuery("FROM Customer WHERE billingAddress.city = :City")
        .setParameter("City", "Lametown");
    Customer c2 = r2.uniqueResult!Customer();
    assert(c2 !is null);
    assert(c2.billingAddress.street == "101001 Robotface");
  }

  @Test("embedded.update")
  void updateTest() {
    Session sess = sessionFactory.openSession();

    auto r1 = sess.createQuery("FROM Customer WHERE billingAddress.city = :City")
        .setParameter("City", "Lametown");
    Customer c1 = r1.uniqueResult!Customer();
    assert(c1 !is null);

    c1.billingAddress.street = "17 Neat Street";
    sess.update(c1);

    // Create a new session to prevent caching.
    sess.close();
    sess = sessionFactory.openSession();

    r1 = sess.createQuery("FROM Customer WHERE billingAddress.city = :City")
        .setParameter("City", "Lametown");
    c1 = r1.uniqueResult!Customer();
    assert(c1 !is null);
    assert(c1.billingAddress.street == "17 Neat Street");

    sess.close();
  }

  @Test("embedded.delete")
  void deleteTest() {
    Session sess = sessionFactory.openSession();

    auto r1 = sess.createQuery("FROM Customer WHERE billingAddress.city = :City")
        .setParameter("City", "Lametown");
    Customer c1 = r1.uniqueResult!Customer();
    assert(c1 !is null);

    sess.remove(c1);

    // Create a new session to prevent caching.
    sess.close();
    sess = sessionFactory.openSession();

    r1 = sess.createQuery("FROM Customer WHERE billingAddress.city = :City")
        .setParameter("City", "Lametown");
    c1 = r1.uniqueResult!Customer();
    assert(c1 is null);

    sess.close();
  }

}
