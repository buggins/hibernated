/**
 * HibernateD - Object-Relation Mapping for D programming language, with interface similar to Hibernate.
 *
 * Source file hibernated/dialects/sqlitedialect.d.
 *
 * This module contains implementation of SQLiteDialect class which provides implementation specific SQL syntax information.
 *
 * Copyright: Copyright 2013
 * License:   $(LINK www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Author:   Vadim Lopatin
 */
module hibernated.dialects.sqlitedialect;

import std.conv;

import hibernated.dialect : Dialect;
import hibernated.metadata;
import hibernated.type;
import ddbc.core : SqlType;


string[] SQLITE_RESERVED_WORDS =
    [
     "ABORT",
     "ACTION",
     "ADD",
     "AFTER",
     "ALL",
     "ALTER",
     "ANALYZE",
     "AND",
     "AS",
     "ASC",
     "ATTACH",
     "AUTOINCREMENT",
     "BEFORE",
     "BEGIN",
     "BETWEEN",
     "BY",
     "CASCADE",
     "CASE",
     "CAST",
     "CHECK",
     "COLLATE",
     "COLUMN",
     "COMMIT",
     "CONFLICT",
     "CONSTRAINT",
     "CREATE",
     "CROSS",
     "CURRENT_DATE",
     "CURRENT_TIME",
     "CURRENT_TIMESTAMP",
     "DATABASE",
     "DEFAULT",
     "DEFERRABLE",
     "DEFERRED",
     "DELETE",
     "DESC",
     "DETACH",
     "DISTINCT",
     "DROP",
     "EACH",
     "ELSE",
     "END",
     "ESCAPE",
     "EXCEPT",
     "EXCLUSIVE",
     "EXISTS",
     "EXPLAIN",
     "FAIL",
     "FOR",
     "FOREIGN",
     "FROM",
     "FULL",
     "GLOB",
     "GROUP",
     "HAVING",
     "IF",
     "IGNORE",
     "IMMEDIATE",
     "IN",
     "INDEX",
     "INDEXED",
     "INITIALLY",
     "INNER",
     "INSERT",
     "INSTEAD",
     "INTERSECT",
     "INTO",
     "IS",
     "ISNULL",
     "JOIN",
     "KEY",
     "LEFT",
     "LIKE",
     "LIMIT",
     "MATCH",
     "NATURAL",
     "NO",
     "NOT",
     "NOTNULL",
     "NULL",
     "OF",
     "OFFSET",
     "ON",
     "OR",
     "ORDER",
     "OUTER",
     "PLAN",
     "PRAGMA",
     "PRIMARY",
     "QUERY",
     "RAISE",
     "REFERENCES",
     "REGEXP",
     "REINDEX",
     "RELEASE",
     "RENAME",
     "REPLACE",
     "RESTRICT",
     "RIGHT",
     "ROLLBACK",
     "ROW",
     "SAVEPOINT",
     "SELECT",
     "SET",
     "TABLE",
     "TEMP",
     "TEMPORARY",
     "THEN",
     "TO",
     "TRANSACTION",
     "TRIGGER",
     "UNION",
     "UNIQUE",
     "UPDATE",
     "USING",
     "VACUUM",
     "VALUES",
     "VIEW",
     "VIRTUAL",
     "WHEN",
     "WHERE",
     ];


class SQLiteDialect : Dialect {
    ///The character specific to this dialect used to close a quoted identifier.
    override char closeQuote() const { return '`'; }
    ///The character specific to this dialect used to begin a quoted identifier.
    override char  openQuote() const { return '`'; }

    // returns string like "BIGINT(20) NOT NULL" or "VARCHAR(255) NULL"
    override string getColumnTypeDefinition(const PropertyInfo pi, const PropertyInfo overrideTypeFrom = null) {
        immutable Type type = overrideTypeFrom !is null ? overrideTypeFrom.columnType : pi.columnType;
        immutable SqlType sqlType = type.getSqlType();
        bool fk = pi is null;
        string nullablility = !fk && pi.nullable ? " NULL" : " NOT NULL";
        string pk = !fk && pi.key ? " PRIMARY KEY" : "";
        string autoinc = !fk && pi.generated ? " AUTOINCREMENT" : "";
        if (!fk && !pi.key && pi.generated) {
            // SQLite3 does not support autoincrement on non-primary key fields.
            return "INTEGER NOT NULL DEFAULT 0";
        }
        string def = "";
        int len = 0;
        string unsigned = "";
        if (cast(NumberType)type !is null) {
            len = (cast(NumberType)type).length;
            unsigned = (cast(NumberType)type).unsigned ? " UNSIGNED" : "";
        }
        if (cast(StringType)type !is null) {
            len = (cast(StringType)type).length;
        }
        string modifiers = unsigned ~ nullablility ~ def ~ pk ~ autoinc;
        string lenmodifiers = "(" ~ to!string(len > 0 ? len : 255) ~ ")" ~ modifiers;
        switch (sqlType) {
            case SqlType.BIGINT:
            case SqlType.BIT:
            case SqlType.BOOLEAN:
            case SqlType.INTEGER:
            case SqlType.NUMERIC:
            case SqlType.SMALLINT:
            case SqlType.TINYINT:
                return "INTEGER" ~ modifiers;
            case SqlType.FLOAT:
            case SqlType.DOUBLE:
            case SqlType.DECIMAL:
                return "REAL" ~ modifiers;
            case SqlType.DATE:
            case SqlType.DATETIME:
            case SqlType.TIME:
            case SqlType.CHAR:
            case SqlType.CLOB:
            case SqlType.LONGNVARCHAR:
            case SqlType.LONGVARBINARY:
            case SqlType.LONGVARCHAR:
            case SqlType.NCHAR:
            case SqlType.NCLOB:
            case SqlType.VARBINARY:
            case SqlType.VARCHAR:
            case SqlType.NVARCHAR:
                return "TEXT" ~ modifiers;
            case SqlType.BLOB:
                return "BLOB";
            default:
                return "TEXT";
        }
    }

    override string getCheckTableExistsSQL(string tableName) {
        return "SELECT name FROM sqlite_master WHERE type='table' AND name=" ~ quoteSqlString(tableName);
    }

    override string getUniqueIndexItemSQL(string indexName, string[] columnNames) {
        return "UNIQUE " ~ createFieldListSQL(columnNames);
    }


    this() {
        addKeywords(SQLITE_RESERVED_WORDS);
    }
}

