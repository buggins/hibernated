module relationkeytest;

import std.algorithm : map, sort;
import std.array : array;
import std.conv : to;
import std.datetime : Date, days;

import hibernated.core;

import testrunner : Test;
import hibernatetest : HibernateTest;

// A many-to-many relation between entities keyed by strings and by dates. The join-table statements used to write
// the keys into the SQL: string keys quoted only by doubling ', so a backslash broke them on MySQL and ClickHouse
// (a key ending in \ ran the literal on into the statement), and date keys as Phobos text ('2019-Sep-15') that
// matches no stored value (#122).
@Entity
class Label {
    @Id
    string name;
    int weight;
    @ManyToMany
    LazyCollection!Holiday holidays;
}

@Entity
class Holiday {
    @Id
    Date day;
    string title;
    @ManyToMany
    LazyCollection!Label labels;
}

// A many-to-one reference to an entity keyed by a date: SQLite returns the foreign key as text, which the relation
// loader's key map must match with the Date key of the loaded entity (#122).
@Entity
class Visit {
    @Id
    long id;
    Holiday holiday;
}

class RelationKeyTest : HibernateTest {
    // ' and \ in every position that matters, including a key that ends in a backslash
    enum quoteName = "O'Brien";
    enum dirName = "C:\\dir\\";
    enum escapedQuoteName = "a\\'b";

    override
    EntityMetaData buildSchema() {
        return new SchemaInfoImpl!(Label, Holiday, Visit);
    }

    private static string[] labelNames(Holiday h) {
        return h.labels.get().map!(l => l.name).array.sort.array;
    }

    private static Date[] holidayDays(Label l) {
        return l.holidays.get().map!(h => h.day).array.sort.array;
    }

    @Test("relationkeys.string-and-date-keys")
    void stringAndDateKeysTest() {
        Date d1 = Date(2019, 9, 15); // not immutable: ddbc binds an immutable(Date) Variant as toString text
        Date d2 = Date(1901, 2, 3);
        {
            Session sess = sessionFactory.openSession();
            scope(exit) sess.close();
            Holiday h1 = new Holiday();
            h1.day = d1;
            h1.title = "one";
            sess.save(h1);
            Holiday h2 = new Holiday();
            h2.day = d2;
            h2.title = "two";
            sess.save(h2);

            Label l1 = new Label();
            l1.name = quoteName;
            l1.holidays = [h1, h2];
            sess.save(l1);
            Label l2 = new Label();
            l2.name = dirName;
            l2.holidays = [h1];
            sess.save(l2);
            Label l3 = new Label();
            l3.name = escapedQuoteName;
            l3.holidays = [h2];
            sess.save(l3);
        }
        {
            // a new session: read from the database, not from the session cache
            Session sess = sessionFactory.openSession();
            scope(exit) sess.close();
            Label l1 = sess.get!Label(quoteName);
            assert(l1 !is null);
            assert(holidayDays(l1) == [d2, d1], to!string(holidayDays(l1)));
            Label l2 = sess.get!Label(dirName);
            assert(l2 !is null);
            assert(holidayDays(l2) == [d1], to!string(holidayDays(l2)));
            Holiday h1 = sess.get!Holiday(d1);
            assert(h1 !is null);
            assert(labelNames(h1) == [quoteName, dirName].sort.array, to!string(labelNames(h1)));
            Holiday h2 = sess.get!Holiday(d2);
            assert(h2 !is null);
            assert(labelNames(h2) == [quoteName, escapedQuoteName].sort.array, to!string(labelNames(h2)));

            // update: l1 loses d2, l2 gains d2
            l1.holidays = [h1];
            l1.weight = 1;
            sess.update(l1);
            l2.holidays = [h1, h2];
            l2.weight = 2;
            sess.update(l2);
        }
        {
            Session sess = sessionFactory.openSession();
            scope(exit) sess.close();
            Label l1 = sess.get!Label(quoteName);
            assert(l1 !is null);
            assert(holidayDays(l1) == [d1], to!string(holidayDays(l1)));
            Label l2 = sess.get!Label(dirName);
            assert(l2 !is null);
            assert(holidayDays(l2) == [d2, d1], to!string(holidayDays(l2)));
            Holiday h2 = sess.get!Holiday(d2);
            assert(h2 !is null);
            assert(labelNames(h2) == [dirName, escapedQuoteName].sort.array, to!string(labelNames(h2)));

            // removing an entity deletes its join-table rows
            sess.remove(l2);
        }
        {
            Session sess = sessionFactory.openSession();
            scope(exit) sess.close();
            assert(sess.get!Label(dirName) is null);
            Holiday h1 = sess.get!Holiday(d1);
            assert(h1 !is null);
            assert(labelNames(h1) == [quoteName], to!string(labelNames(h1)));
            Holiday h2 = sess.get!Holiday(d2);
            assert(h2 !is null);
            assert(labelNames(h2) == [escapedQuoteName], to!string(labelNames(h2)));
            foreach (name; [quoteName, escapedQuoteName])
                sess.remove(sess.get!Label(name));
            foreach (day; [d1, d2])
                sess.remove(sess.get!Holiday(day));
        }
    }

    @Test("relationkeys.many-to-one-date-key")
    void manyToOneDateKeyTest() {
        Date day = Date(2020, 2, 29);
        {
            Session sess = sessionFactory.openSession();
            scope(exit) sess.close();
            Holiday h = new Holiday();
            h.day = day;
            h.title = "leap";
            sess.save(h);
            Visit v = new Visit();
            v.id = 1;
            v.holiday = h;
            sess.save(v);
        }
        {
            Session sess = sessionFactory.openSession();
            scope(exit) sess.close();
            Visit v = sess.get!Visit(1L);
            assert(v !is null);
            assert(v.holiday !is null, "the many-to-one reference to a date-keyed entity wasn't loaded");
            assert(v.holiday.day == day);
            sess.remove(v);
            sess.remove(v.holiday);
        }
    }

    // more relations than one join-table statement takes: they are sent in chunks of 450 rows
    @Test("relationkeys.many-relations")
    void manyRelationsTest() {
        enum count = 460;
        Date first = Date(2000, 1, 1);
        {
            Session sess = sessionFactory.openSession();
            scope(exit) sess.close();
            Holiday[] holidays;
            foreach (i; 0 .. count) {
                Holiday h = new Holiday();
                h.day = first + days(i);
                h.title = "h";
                sess.save(h);
                holidays ~= h;
            }
            Label l = new Label();
            l.name = "many";
            l.holidays = holidays;
            sess.save(l);
        }
        {
            Session sess = sessionFactory.openSession();
            scope(exit) sess.close();
            Label l = sess.get!Label("many");
            assert(l !is null);
            Date[] loaded = holidayDays(l);
            assert(loaded.length == count, to!string(loaded.length));
            assert(loaded[0] == first && loaded[$ - 1] == first + days(count - 1));
            // deletes its 460 join rows; the holidays (2000-01-01 to 2001-04-04) stay until the next schema rebuild:
            // one DELETE each is slow on ClickHouse
            sess.remove(l);
        }
    }
}
