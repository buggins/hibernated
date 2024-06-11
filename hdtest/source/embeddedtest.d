module embeddedtest;

import hibernated.core;

import testrunner : Test;
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

        Customer c2 = new Customer();
        // Single quotes (') are quoted as ('') in SQL.
        c2.name = "Erdrick O'Henry";
        c2.shippingAddress = new Address();
        c2.shippingAddress.street = "21 Grassy Knoll";
        c2.shippingAddress.city = "Warrenton";
        c2.billingAddress = new Address();
        c2.billingAddress.street = "327 Industrial Way";
        c2.billingAddress.city = "Megatropolis";
        long c2Id = sess.save(c2).get!long;
        assert(c2Id > 0);
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

        // Make sure queries on strings with (') characters work.
        auto r3 = sess.createQuery("FROM Customer WHERE name = :Name")
                .setParameter("Name", "Erdrick O'Henry");
        Customer c3 = r3.uniqueResult!Customer();
        assert(c3.name == "Erdrick O'Henry");
        assert(c3.shippingAddress.city == "Warrenton");
    }

    @Test("embedded.read.query-order-by")
    void readQueryOrderByTest() {
        Session sess = sessionFactory.openSession();
        scope(exit) sess.close();

        auto r1 = sess.createQuery("FROM Customer ORDER BY shippingAddress.street DESC");
        Customer[] customers = r1.list!Customer();
        assert(customers.length == 2);
        assert(customers[0].shippingAddress.street == "21 Grassy Knoll");

        auto r2 = sess.createQuery("FROM Customer c ORDER BY c.billingAddress.street ASC");
        customers = r2.list!Customer();
        assert(customers.length == 2);
        assert(customers[0].billingAddress.street == "101001 Robotface");
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
