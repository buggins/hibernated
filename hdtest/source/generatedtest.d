module generatedtest;

import std.datetime;

import hibernated.core;

import testrunner : Test;
import hibernatetest : HibernateTest;

// A class representing a entity with a single generated key.
@Entity
class Generated1 {
    // Generated, we can leave this off and the DB will create it.
    @Id @Generated
    int myId;

    string name;
}

// A class representing a entity with multiple generated values.
@Entity
class Generated2 {
    // Not generated, this must be set in order to save.
    @Id
    int myId;

    // The DB will create this value and it does not need to be set.
    @Generated
    int counter1;

    // The DB will create this value and it does not need to be set.
    @Generated
    DateTime counter2;

    string name;
}

class GeneratedTest : HibernateTest {
    override
    EntityMetaData buildSchema() {
        return new SchemaInfoImpl!(Generated1, Generated2);
    }

    @Test("generated.primary-generated")
    void creation1Test() {
        Session sess = sessionFactory.openSession();
        scope (exit) sess.close();

        Generated1 g1 = new Generated1();
        g1.name = "Bob";
        sess.save(g1);
        // This value should have been detected as empty, populated by the DB, and refreshed.
        int g1Id = g1.myId;
        assert(g1Id != 0);

        g1.name = "Barb";
        sess.update(g1);
        // The ID should not have changed.
        assert(g1.myId == g1Id);
    }

    @Test("generated.non-primary-generated")
    void creation2Test() {
        Session sess = sessionFactory.openSession();
        scope (exit) sess.close();

        Generated2 g2 = new Generated2();
        g2.myId = 2;
        g2.name = "Sam";
        sess.save(g2);

        int g2Id = g2.myId;

        g2.name = "Slom";
        sess.update(g2);

        // The ID should not have changed.
        assert(g2Id == g2.myId);
    }
}
