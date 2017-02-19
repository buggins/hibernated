/**
 * HibernateD - Object-Relation Mapping for D programming language, with interface similar to Hibernate. 
 * 
 * Source file hibernated/dialects/mysqldialect.d.
 *
 * This module contains implementation of MySQLDialect class which provides implementation specific SQL syntax information.
 * 
 * Copyright: Copyright 2013
 * License:   $(LINK www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Author:   Vadim Lopatin
 */
module hibernated.dialects.mysqldialect;

import std.conv;

import hibernated.dialect;
import hibernated.metadata;
import hibernated.type;
import ddbc.core;

string[] MYSQL_RESERVED_WORDS = 
	[
	"ACCESSIBLE", "ADD", "ALL",
	"ALTER", "ANALYZE", "AND",
	"AS", "ASC", "ASENSITIVE",
	"BEFORE", "BETWEEN", "BIGINT",
	"BINARY", "BLOB", "BOTH",
	"BY", "CALL", "CASCADE",
	"CASE", "CHANGE", "CHAR",
	"CHARACTER", "CHECK", "COLLATE",
	"COLUMN", "CONDITION", "CONSTRAINT",
	"CONTINUE", "CONVERT", "CREATE",
	"CROSS", "CURRENT_DATE", "CURRENT_TIME",
	"CURRENT_TIMESTAMP", "CURRENT_USER", "CURSOR",
	"DATABASE", "DATABASES", "DAY_HOUR",
	"DAY_MICROSECOND", "DAY_MINUTE", "DAY_SECOND",
	"DEC", "DECIMAL", "DECLARE",
	"DEFAULT", "DELAYED", "DELETE",
	"DESC", "DESCRIBE", "DETERMINISTIC",
	"DISTINCT", "DISTINCTROW", "DIV",
	"DOUBLE", "DROP", "DUAL",
	"EACH", "ELSE", "ELSEIF",
	"ENCLOSED", "ESCAPED", "EXISTS",
	"EXIT", "EXPLAIN", "FALSE",
	"FETCH", "FLOAT", "FLOAT4",
	"FLOAT8", "FOR", "FORCE",
	"FOREIGN", "FROM", "FULLTEXT",
	"GET", "GRANT", "GROUP",
	"HAVING", "HIGH_PRIORITY", "HOUR_MICROSECOND",
	"HOUR_MINUTE", "HOUR_SECOND", "IF",
	"IGNORE", "IN", "INDEX",
	"INFILE", "INNER", "INOUT",
	"INSENSITIVE", "INSERT", "INT",
	"INT1", "INT2", "INT3",
	"INT4", "INT8", "INTEGER",
	"INTERVAL", "INTO", "IO_AFTER_GTIDS",
	"IO_BEFORE_GTIDS", "IS", "ITERATE",
	"JOIN", "KEY", "KEYS",
	"KILL", "LEADING", "LEAVE",
	"LEFT", "LIKE", "LIMIT",
	"LINEAR", "LINES", "LOAD",
	"LOCALTIME", "LOCALTIMESTAMP", "LOCK",
	"LONG", "LONGBLOB", "LONGTEXT",
	"LOOP", "LOW_PRIORITY", "MASTER_BIND",
	"MASTER_SSL_VERIFY_SERVER_CERT", "MATCH", "MAXVALUE",
	"MEDIUMBLOB", "MEDIUMINT", "MEDIUMTEXT",
	"MIDDLEINT", "MINUTE_MICROSECOND", "MINUTE_SECOND",
	"MOD", "MODIFIES", "NATURAL",
	"NOT", "NO_WRITE_TO_BINLOG", "NULL",
	"NUMERIC", "ON", "OPTIMIZE",
	"OPTION", "OPTIONALLY", "OR",
	"ORDER", "OUT", "OUTER",
	"OUTFILE", "PARTITION", "PRECISION",
	"PRIMARY", "PROCEDURE", "PURGE",
	"RANGE", "READ", "READS",
	"READ_WRITE", "REAL", "REFERENCES",
	"REGEXP", "RELEASE", "RENAME",
	"REPEAT", "REPLACE", "REQUIRE",
	"RESIGNAL", "RESTRICT", "RETURN",
	"REVOKE", "RIGHT", "RLIKE",
	"SCHEMA", "SCHEMAS", "SECOND_MICROSECOND",
	"SELECT", "SENSITIVE", "SEPARATOR",
	"SET", "SHOW", "SIGNAL",
	"SMALLINT", "SPATIAL", "SPECIFIC",
	"SQL", "SQLEXCEPTION", "SQLSTATE",
	"SQLWARNING", "SQL_BIG_RESULT", "SQL_CALC_FOUND_ROWS",
	"SQL_SMALL_RESULT", "SSL", "STARTING",
	"STRAIGHT_JOIN", "TABLE", "TERMINATED",
	"THEN", "TINYBLOB", "TINYINT",
	"TINYTEXT", "TO", "TRAILING",
	"TRIGGER", "TRUE", "UNDO",
	"UNION", "UNIQUE", "UNLOCK",
	"UNSIGNED", "UPDATE", "USAGE",
	"USE", "USING", "UTC_DATE",
	"UTC_TIME", "UTC_TIMESTAMP", "VALUES",
	"VARBINARY", "VARCHAR", "VARCHARACTER",
	"VARYING", "WHEN", "WHERE",
	"WHILE", "WITH", "WRITE",
	"XOR", "YEAR_MONTH", "ZEROFILL",
	"GET", "IO_AFTER_GTIDS", "IO_BEFORE_GTIDS",
	"MASTER_BIND", "ONE_SHOT", "PARTITION",
	"SQL_AFTER_GTIDS", "SQL_BEFORE_GTIDS",
];

class MySQLDialect : Dialect {
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
        string autoinc = !fk && pi.generated ? " AUTO_INCREMENT" : "";
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
                return "BIGINT" ~ modifiers;
                ///sometimes referred to as a type code, that identifies the generic SQL type BINARY.
                //BINARY,
                //sometimes referred to as a type code, that identifies the generic SQL type BIT.
            case SqlType.BIT:
                return "TINYINT" ~ modifiers;
                ///sometimes referred to as a type code, that identifies the generic SQL type BLOB.
            case SqlType.BLOB:
                return "BLOB";
                ///somtimes referred to as a type code, that identifies the generic SQL type BOOLEAN.
            case SqlType.BOOLEAN:
                return "TINYINT" ~ modifiers;
                ///sometimes referred to as a type code, that identifies the generic SQL type CHAR.
            case SqlType.CHAR:
                return "CHAR" ~ lenmodifiers;
                ///sometimes referred to as a type code, that identifies the generic SQL type CLOB.
            case SqlType.CLOB:
                return "MEDIUMTEXT";
                //somtimes referred to as a type code, that identifies the generic SQL type DATALINK.
                    //DATALINK,
                    ///sometimes referred to as a type code, that identifies the generic SQL type DATE.
            case SqlType.DATE:
                return "DATE" ~ modifiers;
                ///sometimes referred to as a type code, that identifies the generic SQL type DATETIME.
            case SqlType.DATETIME:
                return "DATETIME" ~ modifiers;
                ///sometimes referred to as a type code, that identifies the generic SQL type DECIMAL.
            case SqlType.DECIMAL:
                return "DOUBLE" ~ modifiers;
                //sometimes referred to as a type code, that identifies the generic SQL type DISTINCT.
                    //DISTINCT,
                    ///sometimes referred to as a type code, that identifies the generic SQL type DOUBLE.
            case SqlType.DOUBLE:
                return "DOUBLE" ~ modifiers;
                ///sometimes referred to as a type code, that identifies the generic SQL type FLOAT.
            case SqlType.FLOAT:
                return "FLOAT" ~ modifiers;
                ///sometimes referred to as a type code, that identifies the generic SQL type INTEGER.
            case SqlType.INTEGER:
                return "INT" ~ modifiers;
                //sometimes referred to as a type code, that identifies the generic SQL type JAVA_OBJECT.
                    //JAVA_OBJECT,
                    ///sometimes referred to as a type code, that identifies the generic SQL type LONGNVARCHAR.
            case SqlType.LONGNVARCHAR:
                return "VARCHAR" ~ lenmodifiers;
                ///sometimes referred to as a type code, that identifies the generic SQL type LONGVARBINARY.
            case SqlType.LONGVARBINARY:
                return "VARCHAR" ~ lenmodifiers;
                ///sometimes referred to as a type code, that identifies the generic SQL type LONGVARCHAR.
            case SqlType.LONGVARCHAR:
                return "VARCHAR" ~ lenmodifiers;
                ///sometimes referred to as a type code, that identifies the generic SQL type NCHAR
            case SqlType.NCHAR:
                return "NCHAR" ~ lenmodifiers;
                ///sometimes referred to as a type code, that identifies the generic SQL type NCLOB.
            case SqlType.NCLOB:
                return "MEDIUMTEXT";
                ///sometimes referred to as a type code, that identifies the generic SQL type NUMERIC.
            case SqlType.NUMERIC:
                return "DOUBLE" ~ modifiers;
                ///sometimes referred to as a type code, that identifies the generic SQL type NVARCHAR.
            case SqlType.NVARCHAR:
                return "NVARCHAR" ~ lenmodifiers;
                ///sometimes referred to as a type code, that identifies the generic SQL type SMALLINT.
            case SqlType.SMALLINT:
                return "SMALLINT" ~ modifiers;
                //sometimes referred to as a type code, that identifies the generic SQL type XML.
                    //SQLXML,
                    //sometimes referred to as a type code, that identifies the generic SQL type STRUCT.
                    //STRUCT,
                    ///sometimes referred to as a type code, that identifies the generic SQL type TIME.
            case SqlType.TIME:
                return "TIME" ~ modifiers;
                //sometimes referred to as a type code, that identifies the generic SQL type TIMESTAMP.
                    //TIMESTAMP,
                    ///sometimes referred to as a type code, that identifies the generic SQL type TINYINT.
            case SqlType.TINYINT:
                return "TINYINT" ~ modifiers;
                ///sometimes referred to as a type code, that identifies the generic SQL type VARBINARY.
            case SqlType.VARBINARY:
                return "VARCHAR" ~ lenmodifiers;
                ///sometimes referred to as a type code, that identifies the generic SQL type VARCHAR.
            case SqlType.VARCHAR:
                return "VARCHAR" ~ lenmodifiers;
            default:
                return "VARCHAR(255)";
        }
    }


	this() {
		addKeywords(MYSQL_RESERVED_WORDS);
	}
}


unittest {
	Dialect dialect = new MySQLDialect();
	assert(dialect.quoteSqlString("abc") == "'abc'");
	assert(dialect.quoteSqlString("a'b'c") == "'a\\'b\\'c'");
	assert(dialect.quoteSqlString("a\nc") == "'a\\nc'");
	assert(dialect.quoteIfNeeded("blabla") == "blabla");
	assert(dialect.quoteIfNeeded("true") == "`true`");
}
