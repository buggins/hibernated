module cancelquerytest;

import core.atomic : atomicLoad, atomicStore;
import core.thread : Thread;
import core.time : MonoTime, msecs, seconds;
import std.exception : assertThrown, collectException;

import ddbc.core : SQLException, SQLFeatureNotSupportedException, SQLTimeoutException;
import hibernated.core;

import testrunner : AfterClass, BeforeClass, Test;
import hibernatetest : HibernateTest;

// Mapped to a view that takes long to compute (#139).
@Entity
@Table("slow_rows")
class SlowRow {
    @Id
    long id;
}

// A plain entity, to check that the session works after a cancel.
@Entity
class CancelProbe {
    @Id
    long id;

    string name;
}

/// `Session.cancelQuery()` from another thread (#139), and `Query.setTimeout()` (#141).
class CancelQueryTest : HibernateTest {
    override
    EntityMetaData buildSchema() {
        return new SchemaInfoImpl!(SlowRow, CancelProbe);
    }

    private DataSource ownDataSource; // for run(), built once

    /// Runs `sql` on a connection of its own, ignoring errors when `ignoreErrors`.
    void run(string sql, bool ignoreErrors = false) {
        if (ownDataSource is null)
            ownDataSource = buildDataSource(connectionParams);
        Connection conn = ownDataSource.getConnection();
        scope(exit) conn.close();
        Statement stmt = conn.createStatement();
        scope(exit) stmt.close();
        if (ignoreErrors)
            collectException(stmt.executeUpdate(sql));
        else
            stmt.executeUpdate(sql);
    }

    /// The view an earlier run may have left behind would make the schema setup's DROP TABLE fail.
    @BeforeClass
    void dropView() {
        run("DROP VIEW IF EXISTS slow_rows", true);
    }

    @AfterClass
    void dropViewAfter() {
        run("DROP VIEW IF EXISTS slow_rows", true);
    }

    /// Replaces the table the schema setup created for `SlowRow` with a slow view. (The versions in the order of
    /// `HibernateTest.buildDataSource`: the `full` configuration has several.) `forTimeout`: MySQL's SLEEP() just
    /// returns early when the query timeout interrupts it, so the view joins instead (about 20 seconds without the
    /// timeout: cancelQuery() can't stop it, so a timeout that doesn't work fails the test instead of hanging it).
    void createSlowView(bool forTimeout = false) {
        run("DROP VIEW IF EXISTS slow_rows", true); // an earlier test's
        run("DROP TABLE IF EXISTS slow_rows");
        version (USE_SQLITE) {
            run("CREATE VIEW slow_rows AS WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM c "
                ~ "LIMIT 2000000000) SELECT MAX(x) AS id FROM c");
        } else version (USE_MYSQL) {
            if (forTimeout)
                run("CREATE VIEW slow_rows AS SELECT COUNT(*) AS id FROM information_schema.COLLATIONS a, "
                    ~ "information_schema.COLLATIONS b, information_schema.COLLATIONS c, "
                    ~ "(SELECT ID FROM information_schema.COLLATIONS LIMIT 25) d "
                    ~ "WHERE CRC32(CONCAT(a.ID, b.ID, c.ID, d.ID)) = 7");
            else
                run("CREATE VIEW slow_rows AS SELECT SLEEP(2) AS id"); // cancel isn't supported: long enough to try
        } else version (USE_PGSQL) {
            run("CREATE VIEW slow_rows AS SELECT CAST(1 AS bigint) AS id FROM pg_sleep(30)");
        } else version (USE_CLICKHOUSE) {
            run("CREATE VIEW slow_rows AS SELECT toInt64(sum(number)) AS id FROM numbers(100000000000)");
        }
    }

    @Test("cancelquery.from-another-thread")
    void cancelTest() {
        createSlowView();
        Session sess = sessionFactory.openSession();
        scope(exit)
            if (sess.isOpen())
                sess.close();

        sess.cancelQuery(); // no statement yet: nothing happens
        sess.createQuery("FROM CancelProbe").list!CancelProbe();
        sess.cancelQuery(); // the statement is closed: nothing happens (MySQL included)

        shared bool done;
        shared bool unsupported; // MySQL: cancelQuery() threw SQLFeatureNotSupportedException while the query ran
        void cancelUntilDone() {
            // (again until the query ends: the first cancel may come before the statement started)
            while (!atomicLoad(done)) {
                Thread.sleep(300.msecs);
                if (collectException!SQLFeatureNotSupportedException(sess.cancelQuery()) !is null)
                    atomicStore(unsupported, true);
            }
        }
        auto canceller = new Thread(&cancelUntilDone);
        const start = MonoTime.currTime;
        canceller.start();
        auto e = collectException!SQLException(sess.createQuery("FROM SlowRow").list!SlowRow());
        atomicStore(done, true);
        canceller.join();
        version (USE_SQLITE) enum canCancel = true;
        else version (USE_MYSQL) enum canCancel = false;
        else enum canCancel = true;
        static if (canCancel) {
            assert(e !is null, "the query wasn't cancelled");
            assert(e.getSQLState() == "57014", "SQLSTATE " ~ e.getSQLState() ~ ": " ~ e.msg);
            assert(MonoTime.currTime - start < 5.seconds, "the cancel took too long");
            assert(!atomicLoad(unsupported));
        } else {
            assert(e is null, e is null ? "" : e.msg); // the query ran to its end
            assert(atomicLoad(unsupported), "cancelQuery() didn't throw while the query ran");
        }

        // the session still works
        CancelProbe p = new CancelProbe();
        p.id = 1;
        p.name = "after the cancel";
        sess.save(p);
        CancelProbe loaded = sess.createQuery("FROM CancelProbe WHERE id = :Id").setParameter("Id", 1L)
            .uniqueResult!CancelProbe();
        assert(loaded !is null && loaded.name == "after the cancel");

        sess.close();
        sess.cancelQuery(); // after close(): nothing happens
    }

    @Test("cancelquery.timeout")
    void timeoutTest() {
        createSlowView(true);
        Session sess = sessionFactory.openSession();
        scope(exit)
            if (sess.isOpen())
                sess.close();

        Query q = sess.createQuery("FROM SlowRow");
        assert(q.getTimeout() == 0);
        assertThrown!QueryException(q.setTimeout(-1));
        assert(q.getTimeout() == 0);
        assert(q.setTimeout(1) is q && q.getTimeout() == 1);

        void checkTimeout(lazy void call, string what) {
            shared bool done;
            void watchdog() {
                // a timeout that doesn't work fails the test instead of letting it hang (not with MySQL: no cancel)
                const until = MonoTime.currTime + 8.seconds;
                while (!atomicLoad(done) && MonoTime.currTime < until)
                    Thread.sleep(50.msecs);
                if (!atomicLoad(done))
                    collectException(sess.cancelQuery());
            }
            auto dog = new Thread(&watchdog);
            dog.start();
            const start = MonoTime.currTime;
            Exception e = collectException(call);
            atomicStore(done, true);
            dog.join();
            assert(e !is null, what ~ ": the query wasn't stopped");
            assert(cast(SQLTimeoutException) e !is null, what ~ ": " ~ typeid(e).name ~ ": " ~ e.msg);
            version (USE_MYSQL) {
                // the server's SQLSTATE
            } else
                assert((cast(SQLException) e).getSQLState() == "HYT00", what ~ ": SQLSTATE "
                    ~ (cast(SQLException) e).getSQLState() ~ ": " ~ e.msg);
            assert(MonoTime.currTime - start < 5.seconds, what ~ ": the timeout took too long");
        }
        checkTimeout(q.list!SlowRow(), "list");
        checkTimeout(sess.createQuery("FROM SlowRow").setTimeout(1).listRows(), "listRows");

        // the session still works
        CancelProbe p = new CancelProbe();
        p.id = 2;
        p.name = "after the timeout";
        sess.save(p);
        CancelProbe loaded = sess.createQuery("FROM CancelProbe WHERE id = :Id").setParameter("Id", 2L)
            .uniqueResult!CancelProbe();
        assert(loaded !is null && loaded.name == "after the timeout");
    }
}
