module transactiontest;

import std.format;

import hibernated.core;

import testrunner : BeforeClass, Test;
import hibernatetest : HibernateTest;

// A test entity to apply transactions to.
class BankTxn {
    @Id @Generated
    long id;

    string crAcct;  // Account to credit (from).
    string drAcct;  // Account to debit (to).
    int amount;     // Always positive.

    override
    string toString() const {
        return format("{crAcct: \"%s\", drAcct: \"%s\", amount: %d}", crAcct, drAcct, amount);
    }
}

class TransactionTest : HibernateTest {
    override
    EntityMetaData buildSchema() {
        return new SchemaInfoImpl!(BankTxn);
    }

    @BeforeClass
    void enableLogger() {
        // import std.logger;
        // (cast() sharedLog).logLevel = LogLevel.trace;
        // globalLogLevel = LogLevel.trace;
    }

    @Test("transaction.commit")
    void commitTest() {
        Session sess = sessionFactory.openSession();
        Transaction transaction = sess.beginTransaction();
        assert(transaction.isActive() == true);

        BankTxn bankTxn = new BankTxn();
        with (bankTxn) {
            crAcct = "0101";
            drAcct = "0112";
            amount = 5;
        }
        sess.save(bankTxn);
        transaction.commit();
        sess.close();  // Close the session so we can test without a cache.

        sess = sessionFactory.openSession();
        auto q1 = sess.createQuery("FROM BankTxn WHERE amount = :Amount")
                .setParameter("Amount", 5);
        assert(q1.uniqueResult!BankTxn() !is null);
        sess.close();
    }

    @Test("transaction.rollback")
    void rollbackTest() {
        Session sess = sessionFactory.openSession();
        Transaction transaction = sess.beginTransaction();
        assert(transaction.isActive() == true);

        BankTxn bankTxn = new BankTxn();
        with (bankTxn) {
            crAcct = "0101";
            drAcct = "0112";
            amount = 6;
        }
        sess.save(bankTxn);
        transaction.rollback();
        sess.close();  // Close the session so we can test without a cache.

        sess = sessionFactory.openSession();
        auto q1 = sess.createQuery("FROM BankTxn WHERE amount = :Amount")
                .setParameter("Amount", 6);
        assert(q1.uniqueResult!BankTxn() is null);
        sess.close();
    }

    @Test("transaction.closeSessionWithoutCommit")
    void closeSessionWithoutCommitTest() {
        Session sess = sessionFactory.openSession();
        Transaction transaction = sess.beginTransaction();
        assert(transaction.isActive() == true);

        BankTxn bankTxn = new BankTxn();
        with (bankTxn) {
            crAcct = "0101";
            drAcct = "0112";
            amount = 7;
        }
        sess.save(bankTxn);
        // Neither transaction.commit() or transaction.rollback() is called.
        sess.close();  // Close the session so we can test without a cache.

        sess = sessionFactory.openSession();
        auto q1 = sess.createQuery("FROM BankTxn WHERE amount = :Amount")
                .setParameter("Amount", 6);
        assert(q1.uniqueResult!BankTxn() is null);
        sess.close();
    }
}
