module temporaltest;

import std.datetime;
import std.typecons : Nullable;

import hibernated.core;

import testrunner : Test;
import hibernatetest : HibernateTest;

// An entity with date and time properties, some outside 1970 to 2106 (ClickHouse's DateTime range).
@Entity
class Appointment {
    @Id
    long id;

    DateTime at;
    Date day;
    TimeOfDay time;
    @Null
    Nullable!TimeOfDay alarm;
}

class TemporalTest : HibernateTest {
    override
    EntityMetaData buildSchema() {
        return new SchemaInfoImpl!(Appointment);
    }

    @Test("temporal.round-trip")
    void roundTripTest() {
        Session sess = sessionFactory.openSession();
        scope(exit) sess.close();

        Appointment a = new Appointment();
        a.id = 1;
        a.at = DateTime(1960, 5, 1, 10, 30, 15);
        a.day = Date(1901, 2, 3);
        a.time = TimeOfDay(23, 59, 58);
        sess.save(a);

        Appointment b = new Appointment();
        b.id = 2;
        b.at = DateTime(2150, 1, 2, 3, 4, 5);
        b.day = Date(2299, 12, 31);
        b.time = TimeOfDay(0, 0, 1);
        b.alarm = TimeOfDay(6, 45, 0);
        sess.save(b);
        sess.close();

        // a new session: read from the database, not from the session cache
        sess = sessionFactory.openSession();
        Appointment a2 = sess.get!Appointment(1L);
        assert(a2 !is null);
        assert(a2.at == DateTime(1960, 5, 1, 10, 30, 15));
        assert(a2.day == Date(1901, 2, 3));
        assert(a2.time == TimeOfDay(23, 59, 58));
        assert(a2.alarm.isNull);

        Appointment b2 = sess.get!Appointment(2L);
        assert(b2 !is null);
        assert(b2.at == DateTime(2150, 1, 2, 3, 4, 5));
        assert(b2.day == Date(2299, 12, 31));
        assert(b2.time == TimeOfDay(0, 0, 1));
        assert(!b2.alarm.isNull && b2.alarm.get == TimeOfDay(6, 45, 0));
    }
}
