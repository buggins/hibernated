module hibernated.dialects.mysqldialect;

import hibernated.dialect;

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
    override char closeQuote() { return '`'; }
    ///The character specific to this dialect used to begin a quoted identifier.
    override char  openQuote() { return '`'; }

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