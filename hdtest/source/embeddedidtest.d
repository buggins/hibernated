module embeddedidtest;

import std.algorithm : any;

import hibernated.core;

import testrunner : Test;
import hibernatetest : HibernateTest;

// An object representing a composite key, a key with multiple columns to uniquely identify a row.
@Embeddable
class InvoiceId {
    // Each vendor has a unique ID.
    string vendorNo;
    // Vendors independently pick an invoiceNo, which may overlap with other vendors.
    string invoiceNo;

    // Allows session caching to function correctly.
    bool opEquals(const InvoiceId o) const @safe {
        return vendorNo == o.vendorNo && invoiceNo == o.invoiceNo;
    }

    // Useful for debugging.
    override string toString() const @safe {
       return vendorNo ~ ":" ~ invoiceNo;
    }
}

@Entity
class Invoice {
    @EmbeddedId
    InvoiceId invoiceId;

    string currency;
    int amountE4;
}

class EmbeddedIdTest : HibernateTest {
    override
    EntityMetaData buildSchema() {
        return new SchemaInfoImpl!(Invoice, InvoiceId);
    }

    @Test("embeddedid.creation")
    void creationTest() {
        Session sess = sessionFactory.openSession();
        scope(exit) sess.close();

        Invoice invoice = new Invoice();
        invoice.invoiceId = new InvoiceId();
        invoice.invoiceId.vendorNo = "ABC123";
        invoice.invoiceId.invoiceNo = "L1005-2328";
        invoice.currency = "EUR";
        invoice.amountE4 = 120_3400;
        InvoiceId c1Id = sess.save(invoice).get!InvoiceId;
        assert(c1Id.vendorNo == "ABC123" && c1Id.invoiceNo == "L1005-2328");

        Invoice invoice2 = new Invoice();
        invoice2.invoiceId = new InvoiceId();
        invoice2.invoiceId.vendorNo = "ABC123";
        invoice2.invoiceId.invoiceNo = "L1005-2329";
        invoice2.currency = "EUR";
        invoice2.amountE4 = 80_1200;
        InvoiceId c2Id = sess.save(invoice2).get!InvoiceId;
        assert(c2Id.vendorNo == "ABC123" && c2Id.invoiceNo == "L1005-2329");
    }

    @Test("embeddedid.read.query.uniqueResult")
    void readQueryUniqueTest() {
        Session sess = sessionFactory.openSession();
        scope(exit) sess.close();

        auto r1 = sess.createQuery("FROM Invoice WHERE invoiceId.vendorNo = :VendorNo AND invoiceId.invoiceNo = :InvoiceNo")
                .setParameter("VendorNo", "ABC123")
                .setParameter("InvoiceNo", "L1005-2328");
        Invoice i1 = r1.uniqueResult!Invoice();
        assert(i1 !is null);
        assert(i1.invoiceId.vendorNo == "ABC123");
        assert(i1.invoiceId.invoiceNo == "L1005-2328");
        assert(i1.currency == "EUR");
        assert(i1.amountE4 == 120_3400);
    }

    @Test("embeddedid.read.query.list")
    void readQueryListTest() {
        Session sess = sessionFactory.openSession();
        scope(exit) sess.close();

        // A query that only partially covers the primary key.
        auto r2 = sess.createQuery("FROM Invoice WHERE invoiceId.vendorNo = :VendorNo")
                .setParameter("VendorNo", "ABC123");
        Invoice[] i2List = r2.list!Invoice();
        assert(i2List.length == 2);
        assert(i2List.any!((Invoice inv) => inv.invoiceId.vendorNo == "ABC123" && inv.invoiceId.invoiceNo == "L1005-2328"));
        assert(i2List.any!(inv => inv.invoiceId.vendorNo == "ABC123" && inv.invoiceId.invoiceNo == "L1005-2329"));
    }

    @Test("embeddedid.read.get")
    void readGetTest() {
        Session sess = sessionFactory.openSession();
        scope(exit) sess.close();

        InvoiceId id1 = new InvoiceId();
        id1.vendorNo = "ABC123";
        id1.invoiceNo = "L1005-2328";
        Invoice i1 = sess.get!Invoice(id1);
        assert(i1 !is null);
        assert(i1.invoiceId.vendorNo == "ABC123");
        assert(i1.invoiceId.invoiceNo == "L1005-2328");
        assert(i1.currency == "EUR");
        assert(i1.amountE4 == 120_3400);
    }

    @Test("embeddedid.update")
    void updateTest() {
        Session sess = sessionFactory.openSession();

        // Get a record that we will be updating.
        InvoiceId id1 = new InvoiceId();
        id1.vendorNo = "ABC123";
        id1.invoiceNo = "L1005-2328";
        Invoice i1 = sess.get!Invoice(id1);
        assert(i1 !is null);

        i1.currency = "USD";
        sess.update(i1);

        // Create a new session to prevent caching.
        sess.close();
        sess = sessionFactory.openSession();

        Invoice i2 = sess.get!Invoice(id1);
        assert(i2 !is null);
        assert(i2.currency == "USD");

        sess.close();
    }

    @Test("embeddedid.delete")
    void deleteTest() {
        Session sess = sessionFactory.openSession();

        // Get an entity to delete.
        InvoiceId id1 = new InvoiceId();
        id1.vendorNo = "ABC123";
        id1.invoiceNo = "L1005-2328";
        Invoice i1 = sess.get!Invoice(id1);
        assert(i1 !is null);

        sess.remove(i1);

        // Create a new session to prevent caching.
        sess.close();
        sess = sessionFactory.openSession();

        i1 = sess.get!Invoice(id1);
        assert(i1 is null);

        sess.close();
    }

    @Test("embeddedid.refresh")
    void refreshTest() {
        Session sess = sessionFactory.openSession();

        // Create a new record that we can mutate outside the session.
        Invoice invoice = new Invoice();
        invoice.invoiceId = new InvoiceId();
        invoice.invoiceId.vendorNo = "ABC123";
        invoice.invoiceId.invoiceNo = "L1005-2330";
        invoice.currency = "EUR";
        invoice.amountE4 = 54_3200;
        sess.save(invoice).get!InvoiceId;

        // Modify this entity outside the session using a raw SQL query.
        sess.doWork(
                (Connection c) {
                    Statement stmt = c.createStatement();
                    scope (exit) stmt.close();
                    stmt.executeUpdate("UPDATE invoice SET currency = 'USD' "
                            ~ "WHERE vendor_no = 'ABC123' AND invoice_no = 'L1005-2330'");
                });

        // Make sure that the entity picks up the out-of-session changes.
        sess.refresh(invoice);
        assert(invoice.currency == "USD");
    }
}
