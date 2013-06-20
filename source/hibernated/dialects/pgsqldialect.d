/**
 * HibernateD - Object-Relation Mapping for D programming language, with interface similar to Hibernate. 
 * 
 * Source file hibernated/dialects/sqlitedialect.d.
 *
 * This module contains implementation of PGSQLDialect class which provides implementation specific SQL syntax information.
 * 
 * Copyright: Copyright 2013
 * License:   $(LINK www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Author:   Vadim Lopatin
 */
module hibernated.dialects.pgsqldialect;

import std.conv;

import hibernated.dialect;
import hibernated.metadata;
import hibernated.type;
import ddbc.core;


string[] PGSQL_RESERVED_WORDS = 
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


class PGSQLDialect : Dialect {
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
        if (!fk && pi.generated) {
            if (sqlType == SqlType.SMALLINT || sqlType == SqlType.TINYINT)
                return "SERIAL PRIMARY KEY";
            if (sqlType == SqlType.INTEGER)
                return "SERIAL PRIMARY KEY";
            return "BIGSERIAL PRIMARY KEY";
        }
        string def = "";
        int len = 0;
        if (cast(NumberType)type !is null) {
            len = (cast(NumberType)type).length;
        }
        if (cast(StringType)type !is null) {
            len = (cast(StringType)type).length;
        }
        string modifiers = nullablility ~ def ~ pk;
        string lenmodifiers = "(" ~ to!string(len > 0 ? len : 255) ~ ")" ~ modifiers;
        switch (sqlType) {
            case SqlType.BIGINT:
                return "BIGINT" ~ modifiers;
            case SqlType.BIT:
            case SqlType.BOOLEAN:
                return "BOOLEAN" ~ modifiers;
            case SqlType.INTEGER:
                return "INT" ~ modifiers;
            case SqlType.NUMERIC:
                return "INT" ~ modifiers;
            case SqlType.SMALLINT:
                return "SMALLINT" ~ modifiers;
            case SqlType.TINYINT:
                return "SMALLINT" ~ modifiers;
            case SqlType.FLOAT:
                return "FLOAT(24)" ~ modifiers;
            case SqlType.DOUBLE:
            case SqlType.DECIMAL:
                return "FLOAT(53)" ~ modifiers;
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
                return "BYTEA";
            default:
                return "TEXT";
        }
    }
    
    override string getCheckTableExistsSQL(string tableName) {
        return "select relname from pg_class where relname = " ~ quoteSqlString(tableName) ~ " and relkind='r'";
    }
    
    override string getUniqueIndexItemSQL(string indexName, string[] columnNames) {
        return "UNIQUE " ~ createFieldListSQL(columnNames);
    }
    
    /// for some of RDBMS it's necessary to pass additional clauses in query to get generated value (e.g. in Postgres - " returing id"
    override string appendInsertToFetchGeneratedKey(string query, const EntityInfo entity) {
        return query ~ " RETURNING " ~ quoteIfNeeded(entity.getKeyProperty().columnName);
    }

    this() {
        addKeywords(PGSQL_RESERVED_WORDS);
    }
}

