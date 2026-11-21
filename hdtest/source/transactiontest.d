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
        scope(exit) sess.close();
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
    }

    @Test("transaction.rollback")
    void rollbackTest() {
        Session sess = sessionFactory.openSession();
        scope(exit) sess.close();
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
    }

    @Test("transaction.closeSessionWithoutCommit")
    void closeSessionWithoutCommitTest() {
        Session sess = sessionFactory.openSession();
        scope(exit) sess.close();
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
                .setParameter("Amount", 7);
        assert(q1.uniqueResult!BankTxn() is null);
    }

    @Test("transaction.saveAfterCommit")
    void saveAfterCommitTest() {
        Session sess = sessionFactory.openSession();
        scope(exit) sess.close();
        Transaction transaction = sess.beginTransaction();

        BankTxn committed = new BankTxn();
        with (committed) {
            crAcct = "0101";
            drAcct = "0112";
            amount = 8;
        }
        sess.save(committed);
        transaction.commit();
        assert(transaction.isActive() == false);

        // After the commit the session is back in auto-commit mode: this save is not
        // part of an open transaction that closing the session would roll back
        BankTxn afterCommit = new BankTxn();
        with (afterCommit) {
            crAcct = "0101";
            drAcct = "0112";
            amount = 9;
        }
        sess.save(afterCommit);
        sess.close();

        sess = sessionFactory.openSession();
        foreach (amount; [8, 9]) {
            auto q = sess.createQuery("FROM BankTxn WHERE amount = :Amount")
                    .setParameter("Amount", amount);
            assert(q.uniqueResult!BankTxn() !is null);
        }
    }
}
