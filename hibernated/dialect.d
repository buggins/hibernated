/**
 * HibernateD - Object-Relation Mapping for D programming language, with interface similar to Hibernate. 
 * 
 * Hibernate documentation can be found here:
 * $(LINK http://hibernate.org/docs)$(BR)
 * 
 * Source file hibernated/dialect.d.
 *
 * This module contains declaration of Dialect class - base class for implementing RDBMS specific SQL syntax definitions.
 * 
 * Copyright: Copyright 2013
 * License:   $(LINK www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Author:   Vadim Lopatin
 */
module hibernated.dialect;

import std.stdio;
import std.string;

import hibernated.metadata;

/// Represents a dialect of SQL implemented by a particular RDBMS. -- generated from JavaDocs on org.hibernate.dialect.Dialect
abstract class Dialect {

    // returns string like "BIGINT(20) NOT NULL" or "VARCHAR(255) NULL"
    string getColumnTypeDefinition(const PropertyInfo pi, const PropertyInfo overrideTypeFrom = null);

    // returns string like "`columnname` BIGINT(20) NOT NULL" or "VARCHAR(255) NULL"
    string getColumnDefinition(const PropertyInfo pi) {
        return quoteIfNeeded(pi.columnName) ~ " " ~ getColumnTypeDefinition(pi);
    }
    
    ///The character specific to this dialect used to close a quoted identifier.
    char closeQuote() const;
    ///The character specific to this dialect used to begin a quoted identifier.
    char  openQuote() const;
    ///Apply dialect-specific quoting (for `quoted` identifier, replace backtick quotes with dialect specific)
    string quote(string name) const {
        //Apply dialect-specific quoting.
        //By default, the incoming value is checked to see if its first character is the back-tick (`). If so, the dialect specific quoting is applied. 
        if (name.length <=2 || name[0] != '`')
            return name;
        return openQuote() ~ name[1..$-1] ~ closeQuote();
    }

	// should return true for identifiers which cannot be used w/o quote (e.g. keywords)
	bool needQuote(string ident) const {
		return (toUpper(ident) in keywordList) !is null;
	}

	string quoteIfNeeded(string ident) const {
		if (needQuote(ident))
			return quote("`" ~ ident ~ "`");
		return quote(ident);
	}

	protected int[string] keywordList;

	protected void addKeywords(string[] keywords) {
		foreach(s; keywords) {
			keywordList[s] = 1;
		}
	}

    string getDropIndexSQL(string tableName, string indexName) {
        return "DROP INDEX " ~ quoteIfNeeded(indexName) ~ " ON " ~ quoteIfNeeded(tableName);
    }
    string getDropForeignKeySQL(string tableName, string indexName) {
        return "ALTER TABLE " ~ quoteIfNeeded(tableName) ~ " DROP FOREIGN KEY " ~ quoteIfNeeded(indexName);
    }
    string getIndexSQL(string tableName, string indexName, string[] columnNames) {
        return "CREATE INDEX " ~ quoteIfNeeded(indexName) ~ " ON " ~ quoteIfNeeded(tableName) ~ createFieldListSQL(columnNames);
    }
    string getUniqueIndexSQL(string tableName, string indexName, string[] columnNames) {
        return "CREATE UNIQUE INDEX " ~ quoteIfNeeded(indexName) ~ " ON " ~ quoteIfNeeded(tableName) ~ createFieldListSQL(columnNames);
    }
    string getForeignKeySQL(string tableName, string indexName, string[] columnNames, string referencedTableName, string[] referencedFieldNames) {
        assert(columnNames.length == referencedFieldNames.length);
        return "ALTER TABLE " ~ quoteIfNeeded(tableName) ~ " ADD CONSTRAINT " ~ quoteIfNeeded(indexName) ~ " FOREIGN KEY " ~ createFieldListSQL(columnNames) ~ " REFERENCES " ~ quoteIfNeeded(referencedTableName) ~ createFieldListSQL(referencedFieldNames);
    }
    string getCheckTableExistsSQL(string tableName) {
        return "SHOW TABLES LIKE " ~ quoteSqlString(tableName);
    }

    /// returns comma separated quoted identifier list in () parenthesis
    string createFieldListSQL(string[] fields) {
        string res;
        foreach(s; fields) {
            if (res.length > 0)
                res ~= ", ";
            res ~= quoteIfNeeded(s);
        }
        return "(" ~ res ~ ")";
    }

	char getStringQuoteChar() {
		return '\'';
	}

	string quoteSqlString(string s) {
		string res = "'";
		foreach(ch; s) {
			switch(ch) {
				case '\'': res ~= "\\\'"; break;
				case '\"': res ~= "\\\""; break;
				case '\\': res ~= "\\\\"; break;
				case '\0': res ~= "\\n"; break;
				case '\a': res ~= "\\a"; break;
				case '\b': res ~= "\\b"; break;
				case '\f': res ~= "\\f"; break;
				case '\n': res ~= "\\n"; break;
				case '\r': res ~= "\\r"; break;
				case '\t': res ~= "\\t"; break;
				case '\v': res ~= "\\v"; break;
				default:
					res ~= ch;
			}
		}
		res ~= "'";
		//writeln("quoted " ~ s ~ " is " ~ res);
		return res;
	}

/+
    ///Provided we supportsInsertSelectIdentity(), then attach the "select identity" clause to the insert statement.
    string     appendIdentitySelectToInsert(string insertString);
    ///Some dialects support an alternative means to SELECT FOR UPDATE, whereby a "lock hint" is appends to the table name in the from clause.
    string     appendLockHint(LockMode mode, string tableName);
    ///Modifies the given SQL by applying the appropriate updates for the specified lock modes and key columns.
    string     applyLocksToSql(string sql, LockOptions aliasedLockOptions, Map keyColumnNames);
    ///Are string comparisons implicitly case insensitive.
    bool    areStringComparisonsCaseInsensitive();
    ///Does the LIMIT clause come at the start of the SELECT statement, rather than at the end?
    bool    bindLimitParametersFirst();
    ///ANSI SQL defines the LIMIT clause to be in the form LIMIT offset, limit.
    bool    bindLimitParametersInReverseOrder();
    ///Build an instance of the SQLExceptionConverter preferred by this dialect for converting SQLExceptions into Hibernate's JDBCException hierarchy.
    SQLExceptionConverter  buildSQLExceptionConverter();
    ///Hibernate APIs explicitly state that setFirstResult() should be a zero-based offset.
    int    convertToFirstRowValue(int zeroBasedFirstResult);
    ///Create a CaseFragment strategy responsible for handling this dialect's variations in how CASE statements are handled.
    CaseFragment   createCaseFragment();
    ///Create a JoinFragment strategy responsible for handling this dialect's variations in how joins are handled.
    JoinFragment   createOuterJoinFragment();
    ///For the underlying database, is READ_COMMITTED isolation implemented by forcing readers to wait for write locks to be released?
    bool    doesReadCommittedCauseWritersToBlockReaders();
    ///For the underlying database, is REPEATABLE_READ isolation implemented by forcing writers to wait for read locks to be released?
    bool    doesRepeatableReadCauseReadersToBlockWriters();
    ///Do we need to drop constraints before dropping tables in this dialect?
    bool    dropConstraints();
    ///Do we need to drop the temporary table after use?
    bool    dropTemporaryTableAfterUse();
    ///Generally, if there is no limit applied to a Hibernate query we do not apply any limits to the SQL query.
    bool    forceLimitUsage();
    ///Is FOR UPDATE OF syntax supported?
    bool    forUpdateOfColumns();
    ///Generate a temporary table name given the bas table.
    string     generateTemporaryTableName(string baseTableName);
    ///The syntax used to add a column to a table (optional).
    string     getAddColumnString();
    ///The syntax used to add a foreign key constraint to a table.
    string     getAddForeignKeyConstraintString(string constraintName, string[] foreignKey, string referencedTable, string[] primaryKey, bool referencesPrimaryKey);
    ///The syntax used to add a primary key constraint to a table.
    string     getAddPrimaryKeyConstraintString(string constraintName);
    ///Completely optional cascading drop clause
    string     getCascadeConstraintsString();
    ///Get the name of the database type appropriate for casting operations (via the CAST() SQL function) for the given Types typecode.
    string     getCastTypeName(int code);
    string     getColumnComment(string comment);

    ///Slight variation on getCreateTableString().
    string     getCreateMultisetTableString();
    ///Typically dialects which support sequences can create a sequence with a single command.
    protected  string   getCreateSequenceString(string sequenceName);
    ///Overloaded form of getCreateSequenceString(string), additionally taking the initial value and increment size to be applied to the sequence definition.
    protected  string   getCreateSequenceString(string sequenceName, int initialValue, int incrementSize);
    ///Deprecated. Use getCreateSequenceString(string, int, int) instead
    string[]   getCreateSequenceStrings(string sequenceName);
    ///An optional multi-line form for databases which supportsPooledSequences().
    string[]   getCreateSequenceStrings(string sequenceName, int initialValue, int incrementSize);
    ///Command used to create a table.
    string     getCreateTableString();
    ///Get any fragments needing to be postfixed to the command for temporary table creation.
    string     getCreateTemporaryTablePostfix();
    ///Command used to create a temporary table.
    string     getCreateTemporaryTableString();
    ///Get the separator to use for defining cross joins when translating HQL queries.
    string     getCrossJoinSeparator();
    ///Retrieve the command used to retrieve the current timestamp from the database.
    string     getCurrentTimestampSelectString();
    ///The name of the database-specific SQL function for retrieving the current timestamp.
    string     getCurrentTimestampSQLFunctionName();
    ///Retrieve a set of default Hibernate properties for this database.
    Properties     getDefaultProperties();
    ///Get an instance of the dialect specified by the current System properties.
    static Dialect  getDialect();
    ///Get an instance of the dialect specified by the given properties or by the current System properties.
    static Dialect  getDialect(Properties props);
    string     getDropForeignKeyString();

    ///Typically dialects which support sequences can drop a sequence with a single command.
    protected  string   getDropSequenceString(string sequenceName);
    ///The multiline script used to drop a sequence.
    string[]   getDropSequenceStrings(string sequenceName);
    ///Command used to drop a temporary table.
    string     getDropTemporaryTableString();
    ///Retrieves the FOR UPDATE NOWAIT syntax specific to this dialect.
    string     getForUpdateNowaitString();
    ///Get the FOR UPDATE OF column_list NOWAIT fragment appropriate for this dialect given the aliases of the columns to be write locked.
    string     getForUpdateNowaitString(string aliases);
    ///Get the string to append to SELECT statements to acquire locks for this dialect.
    string     getForUpdateString();
    ///Given a lock mode, determine the appropriate for update fragment to use.
    string     getForUpdateString(LockMode lockMode);
    ///Given LockOptions (lockMode, timeout), determine the appropriate for update fragment to use.
    string     getForUpdateString(LockOptions lockOptions);
    ///Get the FOR UPDATE OF column_list fragment appropriate for this dialect given the aliases of the columns to be write locked.
    string     getForUpdateString(string aliases);
    ///Get the FOR UPDATE OF column_list fragment appropriate for this dialect given the aliases of the columns to be write locked.
    string     getForUpdateString(string aliases, LockOptions lockOptions);
    ///Retrieves a map of the dialect's registered functions (functionName => SQLFunction).
    Map    getFunctions();
    ///Get the name of the Hibernate Type associated with the given Types typecode.
    string     getHibernateTypeName(int code);
    ///Get the name of the Hibernate Type associated with the given Types typecode with the given storage specification parameters.
    string     getHibernateTypeName(int code, int length, int precision, int scale);
    ///The syntax used during DDL to define a column as being an IDENTITY.
    protected  string   getIdentityColumnString();
    ///The syntax used during DDL to define a column as being an IDENTITY of a particular type.
    string     getIdentityColumnString(int type);
    ///The keyword used to insert a generated value into an identity column (or null).
    string     getIdentityInsertString();
    ///Get the select command to use to retrieve the last generated IDENTITY value.
    protected  string   getIdentitySelectString();
    ///Get the select command to use to retrieve the last generated IDENTITY value for a particular table
    string     getIdentitySelectString(string table, string column, int type);
    Set    getKeywords();

    ///Apply s limit clause to the query.
    protected  string   getLimitString(string query, bool hasOffset);
    ///Given a limit and an offset, apply the limit clause to the query.
    string     getLimitString(string query, int offset, int limit);
    ///Get a strategy instance which knows how to acquire a database-level lock of the specified mode for this dialect.
    LockingStrategy    getLockingStrategy(Lockable lockable, LockMode lockMode);
    ///The name of the SQL function that transforms a string to lowercase
    string     getLowercaseFunction();
    ///What is the maximum length Hibernate can use for generated aliases?
    int    getMaxAliasLength();
    ///The class (which implements IdentifierGenerator) which acts as this dialects native generation strategy.
    Class  getNativeIdentifierGeneratorClass();
    ///The fragment used to insert a row without specifying any column values.
    string     getNoColumnsInsertString();
    ///The keyword used to specify a nullable column.
    string     getNullColumnString();
    ///Get the select command used retrieve the names of all sequences.
    string     getQuerySequencesString();
    ///Get the string to append to SELECT statements to acquire WRITE locks for this dialect.
    string     getReadLockString(int timeout);
    ///Given a callable statement previously processed by registerResultSetOutParameter(java.sql.CallableStatement, int), extract the ResultSet from the OUT parameter.
    ResultSet  getResultSet(CallableStatement statement);
    ///Given a Types type code, determine an appropriate null value to use in a select clause.
    string     getSelectClauseNullString(int sqlType);
    ///Get the command used to select a GUID from the underlying database.
    string     getSelectGUIDString();
    ///Generate the select expression fragment that will retrieve the next value of a sequence as part of another (typically DML) statement.
    string     getSelectSequenceNextValString(string sequenceName);
    ///Generate the appropriate select statement to to retrieve the next value of a sequence.
    string     getSequenceNextValString(string sequenceName);
    string     getTableComment(string comment);

    string     getTableTypeString();

    ///Get the name of the database type associated with the given Types typecode.
    string     getTypeName(int code);
    ///Get the name of the database type associated with the given Types typecode with the given storage specification parameters.
    string     getTypeName(int code, int length, int precision, int scale);
    ViolatedConstraintNameExtracter    getViolatedConstraintNameExtracter();

    ///Get the string to append to SELECT statements to acquire WRITE locks for this dialect.
    string     getWriteLockString(int timeout);
    ///Does this dialect support the ALTER TABLE syntax?
    bool    hasAlterTable();
    ///Whether this dialect have an Identity clause added to the data type or a completely separate identity data type
    bool    hasDataTypeInIdentityColumn();
    bool    hasSelfReferentialForeignKeyBug();

    ///Should the value returned by getCurrentTimestampSelectString() be treated as callable.
    bool    isCurrentTimestampSelectStringCallable();
    ///If this dialect supports specifying lock timeouts, are those timeouts rendered into the SQL string as parameters.
    bool    isLockTimeoutParameterized();
    ///The character specific to this dialect used to begin a quoted identifier.
    char   openQuote();
    ///Does the dialect require that temporary table DDL statements occur in isolation from other statements? This would be the case if the creation would cause any current transaction to get committed implicitly.
    bool    performTemporaryTableDDLInIsolation();
    ///Do we need to qualify index names with the schema name?
    bool    qualifyIndexName();
    ///Subclasses register a type name for the given type code and maximum column length.
    protected  void     registerColumnType(int code, int capacity, string name);
    ///Subclasses register a type name for the given type code.
    protected  void     registerColumnType(int code, string name);
    protected  void     registerFunction(string name, SQLFunction function);

    ///Registers a Hibernate Type name for the given Types type code and maximum column length.
    protected  void     registerHibernateType(int code, int capacity, string name);
    ///Registers a Hibernate Type name for the given Types type code.
    protected  void     registerHibernateType(int code, string name);
    protected  void     registerKeyword(string word);

    ///Registers an OUT parameter which will be returning a ResultSet.
    int    registerResultSetOutParameter(CallableStatement statement, int position);
    ///Does this dialect require that parameters appearing in the SELECT clause be wrapped in cast() calls to tell the db parser the expected type.
    bool    requiresCastingOfParametersInSelectClause();
    ///Does this dialect support using a JDBC bind parameter as an argument to a function or procedure call?
    bool    supportsBindAsCallableArgument();
    bool    supportsCascadeDelete();

    ///Does this dialect support definition of cascade delete constraints which can cause circular chains?
    bool    supportsCircularCascadeDeleteConstraints();
    ///Does this dialect support column-level check constraints?
    bool    supportsColumnCheck();
    bool    supportsCommentOn();

    ///Does this dialect support a way to retrieve the database's current timestamp value?
    bool    supportsCurrentTimestampSelection();
    ///Does this dialect support empty IN lists? For example, is [where XYZ in ()] a supported construct?
    bool    supportsEmptyInList();
    ///Does the dialect support an exists statement in the select clause?
    bool    supportsExistsInSelect();
    ///Expected LOB usage pattern is such that I can perform an insert via prepared statement with a parameter binding for a LOB value without crazy casting to JDBC driver implementation-specific classes...
    bool    supportsExpectedLobUsagePattern();
    ///Does this dialect support identity column key generation?
    bool    supportsIdentityColumns();
    bool    supportsIfExistsAfterTableName();

    bool    supportsIfExistsBeforeTableName();

    ///Does the dialect support some form of inserting and selecting the generated IDENTITY value all in the same statement.
    bool    supportsInsertSelectIdentity();
    ///Does this dialect support some form of limiting query results via a SQL clause?
    bool    supportsLimit();
    ///Does this dialect's LIMIT support (if any) additionally support specifying an offset?
    bool    supportsLimitOffset();
    ///Does the dialect support propogating changes to LOB values back to the database? Talking about mutating the internal value of the locator as opposed to supplying a new locator instance...
    bool    supportsLobValueChangePropogation();
    ///Informational metadata about whether this dialect is known to support specifying timeouts for requested lock acquisitions.
    bool    supportsLockTimeouts();
    bool    supportsNotNullUnique();

    ///Does this dialect support FOR UPDATE in conjunction with outer joined rows?
    bool    supportsOuterJoinForUpdate();
    ///Does this dialect support parameters within the SELECT clause of INSERT ...
    bool    supportsParametersInInsertSelect();
    ///Does this dialect support "pooled" sequences.
    bool    supportsPooledSequences();
    ///Does this dialect support asking the result set its positioning information on forward only cursors.
    bool    supportsResultSetPositionQueryMethodsOnForwardOnlyCursor();
    ///Is this dialect known to support what ANSI-SQL terms "row value constructor" syntax; sometimes called tuple syntax.
    bool    supportsRowValueConstructorSyntax();
    ///If the dialect supports row values, does it offer such support in IN lists as well? For example, "...
    bool    supportsRowValueConstructorSyntaxInInList();
    ///Does this dialect support sequences?
    bool    supportsSequences();
    ///Does this dialect support referencing the table being mutated in a subquery.
    bool    supportsSubqueryOnMutatingTable();
    ///Are subselects supported as the left-hand-side (LHS) of IN-predicates.
    bool    supportsSubselectAsInPredicateLHS();
    ///Does this dialect support table-level check constraints?
    bool    supportsTableCheck();
    ///Does this dialect support temporary tables?
    bool    supportsTemporaryTables();
    ///Does this dialect support `count(a,b)`?
    bool    supportsTupleCounts();
    ///Does this dialect support `count(distinct a,b)`?
    bool    supportsTupleDistinctCounts();
    ///Is it supported to materialize a LOB locator outside the transaction in which it was created? Again, part of the trickiness here is the fact that this is largely driver dependent.
    bool    supportsUnboundedLobLocatorMaterialization();
    ///Does this dialect support UNION ALL, which is generally a faster variant of UNION?
    bool    supportsUnionAll();
    ///Does this dialect support the UNIQUE column syntax?
    bool    supportsUnique();
    ///Does this dialect support adding Unique constraints via create and alter table ?
    bool    supportsUniqueConstraintInCreateAlterTable();
    ///Does this dialect support bind variables (i.e., prepared statement parameters) for its limit/offset?
    bool    supportsVariableLimit();
    ///The SQL literal value to which this database maps bool values.
    string     toBooleanValueString(bool bool);
    ///Meant as a means for end users to affect the select strings being sent to the database and perhaps manipulate them in some fashion.
    string     transformSelectString(string select);
    ///Should LOBs (both BLOB and CLOB) be bound using stream operations (i.e.
    bool    useInputStreamToInsertBlob();
    ///Does the LIMIT clause take a "maximum" row number instead of a total number of returned rows? This is easiest understood via an example.
    bool    useMaxForLimit();
+/
}

