module hibernated.core;

import std.ascii;
import std.algorithm;
import std.exception;
import std.array;
import std.string;
import std.conv;
import std.stdio;

import hibernated.annotations;
import hibernated.metadata;
import hibernated.type;

class HibernatedException : Exception {
    this(string msg, string f = __FILE__, size_t l = __LINE__) { super(msg, f, l); }
    this(Exception causedBy, string f = __FILE__, size_t l = __LINE__) { super(causedBy.msg, f, l); }
}

class SyntaxError : HibernatedException {
	this(string msg, string f = __FILE__, size_t l = __LINE__) { super(msg, f, l); }
}

struct FromClauseItem {
	string entityName;
	EntityInfo entity;
	string entityAlias;
}

struct OrderByClauseItem {
	FromClauseItem * aliasPtr;
	PropertyInfo prop;
	bool asc;
}

struct SelectClauseItem {
	FromClauseItem * aliasPtr;
	PropertyInfo prop;
}

class QueryParser {
	string query;
	EntityMetaData metadata;
	Token[] tokens;
	FromClauseItem[] fromClause;
	string[] parameterNames;
	OrderByClauseItem[] orderByClause;
	SelectClauseItem[] selectClause;
	this(EntityMetaData metadata, string query) {
		this.metadata = metadata;
		this.query = query;
		tokens = tokenize(query.dup);
		parse();
	}

	void parse() {
		processParameterNames(0, cast(int)tokens.length); // replace pairs {: Ident} with single Parameter token
		int len = cast(int)tokens.length;
		//writeln("Query tokens: " ~ to!string(len));
		int fromPos = findKeyword(KeywordType.FROM);
		int selectPos = findKeyword(KeywordType.SELECT);
		int wherePos = findKeyword(KeywordType.WHERE);
		int orderPos = findKeyword(KeywordType.ORDER);
		enforceEx!SyntaxError(fromPos >= 0, "No FROM clause in query " ~ query);
		enforceEx!SyntaxError(selectPos <= 0, "SELECT clause should be first - invalid query " ~ query);
		enforceEx!SyntaxError(wherePos == -1 || wherePos > fromPos, "Invalid WHERE position in query " ~ query);
		enforceEx!SyntaxError(orderPos == -1 || (orderPos < tokens.length - 2 && tokens[orderPos + 1].keyword == KeywordType.BY), "Invalid ORDER BY in query " ~ query);
		enforceEx!SyntaxError(orderPos == -1 || orderPos > fromPos, "Invalid ORDER BY position in query " ~ query);
		int fromEnd = len;
		if (orderPos >= 0)
			fromEnd = orderPos;
		if (wherePos >= 0)
			fromEnd = wherePos;
		int whereEnd = wherePos < 0 ? -1 : (orderPos >= 0 ? orderPos : len);
		int orderEnd = orderPos < 0 ? -1 : len;
		parseFromClause(fromPos + 1, fromEnd);
		if (selectPos == 0 && selectPos < fromPos - 1)
			parseSelectClause(selectPos + 1, fromPos);
		if (wherePos >= 0 && whereEnd > wherePos)
			parseWhereClause(wherePos + 1, whereEnd);
		if (orderPos >= 0 && orderEnd > orderPos)
			parseOrderClause(orderPos + 2, orderEnd);
	}

	private void updateEntity(EntityInfo entity, string name) {
		foreach(t; tokens) {
			if (t.type == TokenType.Ident && t.text == name) {
				t.entity = entity;
				t.type = TokenType.Entity;
			}
		}
	}

	private void updateAlias(EntityInfo entity, string name) {
		foreach(t; tokens) {
			if (t.type == TokenType.Ident && t.text == name) {
				t.entity = entity;
				t.type = TokenType.Alias;
			}
		}
	}

	private void splitCommaDelimitedList(int start, int end, void delegate(int, int) callback) {
		//writeln("SPLIT " ~ to!string(start) ~ " .. " ~ to!string(end));
		int len = cast(int)tokens.length;
		int p = start;
		for (int i = start; i < end; i++) {
			if (tokens[i].type == TokenType.Comma || i == end - 1) {
				enforceEx!SyntaxError(tokens[i].type != TokenType.Comma || i != end - 1, "Invalid comma at end of list - in query " ~ query);
				int endp = i < end - 1 ? i : end;
				enforceEx!SyntaxError(endp > p, "Invalid comma delimited list - in query " ~ query);
				callback(p, endp);
				p = i + 1;
			}
		}
	}

	void parseFromClause(int start, int end) {
		enforceEx!SyntaxError(start < end, "Invalid FROM clause in query " ~ query);
		// minimal support:
		//    Entity
		//    Entity alias
		//    Entity AS alias
		enforceEx!SyntaxError(tokens[start].type == TokenType.Ident, "Entity name identifier expected in FROM clause in query " ~ query);
		string entityName = cast(string)tokens[start].text;
		EntityInfo ei = metadata.findEntity(entityName);
		updateEntity(ei, entityName);
		string aliasName = null;
		int p = start + 1;
		if (p < end && tokens[p].type == TokenType.Keyword && tokens[p].keyword == KeywordType.AS)
			p++;
		if (p < end) {
			enforceEx!SyntaxError(tokens[p].type == TokenType.Ident, "Alias name identifier expected in FROM clause in query " ~ query);
			aliasName = cast(string)tokens[p].text;
			p++;
		}
		enforceEx!SyntaxError(p == end, "Extra items in FROM clause (only simple FROM Entity [[as] alias] supported so far) - in query " ~ query);
		if (aliasName != null)
			updateAlias(ei, aliasName);
		fromClause = new FromClauseItem[1];
		fromClause[0].entityName = entityName;
		fromClause[0].entity = ei;
		fromClause[0].entityAlias = aliasName;
	}

	// in pairs {: Ident} replace type of ident with Parameter 
	void processParameterNames(int start, int end) {
		for (int i = start; i < end; i++) {
			if (tokens[i].type == TokenType.Parameter) {
				parameterNames ~= cast(string)tokens[i].text;
			}
		}
	}

	FromClauseItem * findFromClauseByAlias(string aliasName) {
		foreach(ref m; fromClause) {
			if (m.entityAlias == aliasName)
				return &m;
		}
		throw new SyntaxError("Cannot find FROM alias by name " ~ aliasName ~ " - in query " ~ query);
	}

	void addSelectClauseItem(string aliasName, string propertyName) {
		FromClauseItem * from = aliasName == null ? &fromClause[0] : findFromClauseByAlias(aliasName);
		SelectClauseItem item;
		item.aliasPtr = from;
		item.prop = propertyName != null ? from.entity.findProperty(propertyName) : null;
		selectClause ~= item;
		//insertInPlace(selectClause, 0, item);
	}

	void addOrderByClauseItem(string aliasName, string propertyName, bool asc) {
		FromClauseItem * from = aliasName == null ? &fromClause[0] : findFromClauseByAlias(aliasName);
		OrderByClauseItem item;
		item.aliasPtr = from;
		item.prop = from.entity.findProperty(propertyName);
		item.asc = asc;
		orderByClause ~= item;
		//insertInPlace(orderByClause, 0, item);
	}
	
	void parseSelectClauseItem(int start, int end) {
		// for each comma delimited item
		// in current version it can only be
		// {property}  or  {alias . property}
		//writeln("SELECT ITEM: " ~ to!string(start) ~ " .. " ~ to!string(end));
		if (start == end - 1) {
			// no alias
			enforceEx!SyntaxError(tokens[start].type == TokenType.Ident || tokens[start].type == TokenType.Alias, "Property name or alias expected in SELECT clause in query " ~ query);
			if (tokens[start].type == TokenType.Ident)
				addSelectClauseItem(null, cast(string)tokens[start].text);
			else
				addSelectClauseItem(cast(string)tokens[start].text, null);
		} else if (start == end - 3) {
			enforceEx!SyntaxError(tokens[start].type == TokenType.Alias, "Entity alias expected in SELECT clause in query " ~ query);
			enforceEx!SyntaxError(tokens[start + 1].type == TokenType.Dot, "Dot expected after entity alias in SELECT clause in query " ~ query);
			enforceEx!SyntaxError(tokens[start + 2].type == TokenType.Ident, "Property name expected after entity alias in SELECT clause in query " ~ query);
			addSelectClauseItem(cast(string)tokens[start].text, cast(string)tokens[start + 2].text);
		} else {
			enforceEx!SyntaxError(false, "Invalid SELECT clause in query " ~ query);
		}
	}

	void parseOrderByClauseItem(int start, int end) {
		// for each comma delimited item
		// in current version it can only be
		// {property}  or  {alias . property} optionally followed by ASC or DESC
		//writeln("ORDER BY ITEM: " ~ to!string(start) ~ " .. " ~ to!string(end));
		bool asc = true;
		if (tokens[end - 1].type == TokenType.Keyword && tokens[end - 1].keyword == KeywordType.ASC) {
			end--;
		} else if (tokens[end - 1].type == TokenType.Keyword && tokens[end - 1].keyword == KeywordType.DESC) {
			asc = false;
			end--;
		}
		enforceEx!SyntaxError(start < end, "Empty ORDER BY clause item in query " ~ query);
		if (start == end - 1) {
			// no alias
			enforceEx!SyntaxError(tokens[start].type == TokenType.Ident, "Property name expected in ORDER BY clause in query " ~ query);
			addOrderByClauseItem(null, cast(string)tokens[start].text, asc);
		} else if (start == end - 3) {
			enforceEx!SyntaxError(tokens[start].type == TokenType.Alias, "Entity alias expected in ORDER BY clause in query " ~ query);
			enforceEx!SyntaxError(tokens[start + 1].type == TokenType.Dot, "Dot expected after entity alias in ORDER BY clause in query " ~ query);
			enforceEx!SyntaxError(tokens[start + 2].type == TokenType.Ident, "Property name expected after entity alias in ORDER BY clause in query " ~ query);
			addOrderByClauseItem(cast(string)tokens[start].text, cast(string)tokens[start + 2].text, asc);
		} else {
			//writeln("range: " ~ to!string(start) ~ " .. " ~ to!string(end));
			enforceEx!SyntaxError(false, "Invalid ORDER BY clause (expected {property [ASC | DESC]} or {alias.property [ASC | DESC]} ) in query " ~ query);
		}
	}
	
	void parseSelectClause(int start, int end) {
		enforceEx!SyntaxError(start < end, "Invalid SELECT clause in query " ~ query);
		splitCommaDelimitedList(start, end, &parseSelectClauseItem);
	}

	void parseWhereClause(int start, int end) {
		enforceEx!SyntaxError(start < end, "Invalid WHERE clause in query " ~ query);
	}
	
	void parseOrderClause(int start, int end) {
		enforceEx!SyntaxError(start < end, "Invalid ORDER BY clause in query " ~ query);
		splitCommaDelimitedList(start, end, &parseOrderByClauseItem);
	}
	
	/// returns position of keyword in tokens array, -1 if not found
	int findKeyword(KeywordType k, int startFrom = 0) {
		for (int i = startFrom; i < tokens.length; i++) {
			if (tokens[i].type == TokenType.Keyword && tokens[i].keyword == k)
				return i;
		}
		return -1;
	}

}

enum KeywordType {
	NONE,
	SELECT,
	FROM,
	WHERE,
	ORDER,
	BY,
	ASC,
	DESC,
	JOIN,
	INNER,
	OUTER,
	LEFT,
	RIGHT,
	LIKE,
	IN,
	IS,
	NOT,
	NULL,
	AS,
	AND,
	OR,
	BETWEEN,
	DIV,
	MOD,
}

KeywordType isKeyword(string str) {
	return isKeyword(str.dup);
}

KeywordType isKeyword(char[] str) {
	char[] s = toUpper(str);
	if (s=="SELECT") return KeywordType.SELECT;
	if (s=="FROM") return KeywordType.FROM;
	if (s=="WHERE") return KeywordType.WHERE;
    if (s=="ORDER") return KeywordType.ORDER;
    if (s=="BY") return KeywordType.BY;
    if (s=="ASC") return KeywordType.ASC;
    if (s=="DESC") return KeywordType.DESC;
    if (s=="JOIN") return KeywordType.JOIN;
    if (s=="INNER") return KeywordType.INNER;
    if (s=="OUTER") return KeywordType.OUTER;
    if (s=="LEFT") return KeywordType.LEFT;
    if (s=="RIGHT") return KeywordType.RIGHT;
    if (s=="LIKE") return KeywordType.LIKE;
    if (s=="IN") return KeywordType.IN;
    if (s=="IS") return KeywordType.IS;
    if (s=="NOT") return KeywordType.NOT;
    if (s=="NULL") return KeywordType.NULL;
    if (s=="AS") return KeywordType.AS;
    if (s=="AND") return KeywordType.AND;
    if (s=="OR") return KeywordType.OR;
    if (s=="BETWEEN") return KeywordType.BETWEEN;
	if (s=="DIV") return KeywordType.DIV;
	if (s=="MOD") return KeywordType.MOD;
	return KeywordType.NONE;
}

unittest {
	assert(isKeyword("Null") == KeywordType.NULL);
	assert(isKeyword("from") == KeywordType.FROM);
	assert(isKeyword("SELECT") == KeywordType.SELECT);
	assert(isKeyword("blabla") == KeywordType.NONE);
}

enum OperatorType {
	NONE,
	EQ, // ==
	NE, // != <>
	LT, // <
	GT, // >
	LE, // <=
	GE, // >=
	MUL,// *
	ADD,// +
	SUB,// -
	DIV,// /
}

OperatorType isOperator(char[] s, ref int i) {
	int len = cast(int)s.length;
	char ch = s[i];
	char ch2 = i < len - 1 ? s[i + 1] : 0;
	//char ch3 = i < len - 2 ? s[i + 2] : 0;
	if (ch == '=' && ch2 == '=') { i++; return OperatorType.EQ; } // ==
	if (ch == '!' && ch2 == '=') { i++; return OperatorType.NE; } // !=
	if (ch == '<' && ch2 == '>') { i++; return OperatorType.NE; } // <>
	if (ch == '<' && ch2 == '=') { i++; return OperatorType.LE; } // <=
	if (ch == '>' && ch2 == '=') { i++; return OperatorType.GE; } // >=
	if (ch == '=') return OperatorType.EQ; // =
	if (ch == '<') return OperatorType.LT; // <
	if (ch == '>') return OperatorType.GT; // <
	if (ch == '*') return OperatorType.MUL; // <
	if (ch == '+') return OperatorType.ADD; // <
	if (ch == '-') return OperatorType.SUB; // <
	if (ch == '/') return OperatorType.DIV; // <
	return OperatorType.NONE;
}


enum TokenType {
	Keyword,      // WHERE
	Ident,        // ident
	Number,       // 25   13.5e-10
	String,       // 'string'
	Operator,     // == != <= >= < > + - * /
	Dot,          // .
	OpenBracket,  // (
	CloseBracket, // )
	Colon,        // :
	Comma,        // ,
	Entity,       // entity name
	Field,        // field name of some entity
	Alias,        // alias name of some entity
	Parameter,    // ident after :
}

class Token {
	TokenType type;
	KeywordType keyword = KeywordType.NONE;
	OperatorType operator = OperatorType.NONE;
	char[] text;
	char[] spaceAfter;
	EntityInfo entity;
	PropertyInfo field;
	this(TokenType type, string text) {
		this.type = type;
		this.text = text.dup;
	}
	this(TokenType type, char[] text) {
		this.type = type;
		this.text = text;
	}
	this(KeywordType keyword, char[] text) {
		this.type = TokenType.Keyword;
		this.keyword = keyword;
		this.text = text;
	}
	this(OperatorType op, char[] text) {
		this.type = TokenType.Operator;
		this.operator = op;
		this.text = text;
	}
}

Token[] tokenize(string s) {
	return tokenize(s.dup);
}

Token[] tokenize(char[] s) {
	Token[] res;
	int startpos = 0;
	int state = 0;
	int len = cast(int)s.length;
	for (int i=0; i<len; i++) {
		char ch = s[i];
		char ch2 = i < len - 1 ? s[i + 1] : 0;
		char ch3 = i < len - 2 ? s[i + 2] : 0;
		char[] text;
		bool quotedIdent = ch == '`';
		startpos = i;
		OperatorType op = isOperator(s, i);
		if (op != OperatorType.NONE) {
			// operator
			res ~= new Token(op, s[startpos .. i + 1]);
		} else if (ch == ':' && (isAlpha(ch2) || ch2=='_')) {
			// parameter name
		    i++;
			// && state == 0
			for(int j=i; j<len; j++) {
				if (isAlphaNum(s[j])) {
					text ~= s[j];
					i = j;
				} else {
					break;
				}
			}
			enforceEx!SyntaxError(text.length > 0, "Invalid parameter name near " ~ cast(string)s[startpos .. $]);
			res ~= new Token(TokenType.Parameter, text);
		} else if (isAlpha(ch) || ch=='_' || quotedIdent) {
			// identifier or keyword
			if (quotedIdent) {
				i++;
				enforceEx!SyntaxError(i < len - 1, "Invalid quoted identifier near " ~ cast(string)s[startpos .. $]);
			}
			// && state == 0
			for(int j=i; j<len; j++) {
				if (isAlphaNum(s[j])) {
					text ~= s[j];
					i = j;
				} else {
					break;
				}
			}
			enforceEx!SyntaxError(text.length > 0, "Invalid quoted identifier near " ~ cast(string)s[startpos .. $]);
			if (quotedIdent) {
				enforceEx!SyntaxError(i < len - 1 && s[i + 1] == '`', "Invalid quoted identifier near " ~ cast(string)s[startpos .. $]);
				i++;
			}
			KeywordType keywordId = isKeyword(text);
			if (keywordId != KeywordType.NONE && !quotedIdent)
				res ~= new Token(keywordId, text);
			else
				res ~= new Token(TokenType.Ident, text);
		} else if (isWhite(ch)) {
			// whitespace
			for(int j=i; j<len; j++) {
				if (isWhite(s[j])) {
					text ~= s[j];
					i = j;
				} else {
					break;
				}
			}
			// don't add whitespace to lexer results as separate token
			// add as spaceAfter
			if (res.length > 0) {
				res[$ - 1].spaceAfter = text;
			}
		} else if (ch == '\'') {
			// string constant
			i++;
			for(int j=i; j<len; j++) {
				if (s[j] != '\'') {
					text ~= s[j];
					i = j;
				} else {
					break;
				}
			}
			enforceEx!SyntaxError(i < len - 1 && s[i + 1] == '\'', "Unfinished string near " ~ cast(string)s[startpos .. $]);
			i++;
			res ~= new Token(TokenType.String, text);
		} else if (isDigit(ch) || (ch == '.' && isDigit(ch2))) {
			// numeric constant
			if (ch == '.') {
				// .25
				text ~= '.';
				i++;
				for(int j = i; j<len; j++) {
					if (isDigit(s[j])) {
						text ~= s[j];
						i = j;
					} else {
						break;
					}
				}
			} else {
				// 123
				for(int j=i; j<len; j++) {
					if (isDigit(s[j])) {
						text ~= s[j];
						i = j;
					} else {
						break;
					}
				}
				// .25
				if (i < len - 1 && s[i + 1] == '.') {
					text ~= '.';
					i++;
					for(int j = i; j<len; j++) {
						if (isDigit(s[j])) {
							text ~= s[j];
							i = j;
						} else {
							break;
						}
					}
				}
			}
			if (i < len - 1 && toLower(s[i + 1]) == 'e') {
				text ~= s[i+1];
				i++;
				if (i < len - 1 && (s[i + 1] == '-' || s[i + 1] == '+')) {
					text ~= s[i+1];
					i++;
				}
				enforceEx!SyntaxError(i < len - 1 && isDigit(s[i]), "Invalid number near " ~ cast(string)s[startpos .. $]);
				for(int j = i; j<len; j++) {
					if (isDigit(s[j])) {
						text ~= s[j];
						i = j;
					} else {
						break;
					}
				}
			}
			enforceEx!SyntaxError(i >= len - 1 || !isAlpha(s[i]), "Invalid number near " ~ cast(string)s[startpos .. $]);
			res ~= new Token(TokenType.Number, text);
		} else if (ch == '.') {
			res ~= new Token(TokenType.Dot, ".");
		} else if (ch == '(') {
			res ~= new Token(TokenType.OpenBracket, "(");
		} else if (ch == ')') {
			res ~= new Token(TokenType.CloseBracket, ")");
		} else if (ch == ':') {
			res ~= new Token(TokenType.Colon, ":");
		} else if (ch == ',') {
			res ~= new Token(TokenType.Comma, ",");
		} else {
			enforceEx!SyntaxError(false, "Invalid character near " ~ cast(string)s[startpos .. $]);
		}
	}
	return res;
}

unittest {
	Token[] tokens;
	tokens = tokenize("SELECT a From User a where a.flags = 12 AND a.name='john' ORDER BY a.idx ASC");
	assert(tokens.length == 23);
	assert(tokens[0].type == TokenType.Keyword);
	assert(tokens[2].type == TokenType.Keyword);
	assert(tokens[5].type == TokenType.Keyword);
	assert(tokens[5].text == "where");
	assert(tokens[10].type == TokenType.Number);
	assert(tokens[10].text == "12");
	assert(tokens[16].type == TokenType.String);
	assert(tokens[16].text == "john");
	assert(tokens[22].type == TokenType.Keyword);
	assert(tokens[22].text == "ASC");

	EntityMetaData schema = new SchemaInfoImpl!(User, Customer);
	QueryParser parser = new QueryParser(schema, "SELECT a FROM User AS a WHERE id = :Id AND name != :skipName ORDER BY name, a.flags DESC");
	assert(parser.parameterNames.length == 2);
	//writeln("param1=" ~ parser.parameterNames[0]);
	//writeln("param2=" ~ parser.parameterNames[1]);
	assert(parser.parameterNames[0] == "Id");
	assert(parser.parameterNames[1] == "skipName");
	assert(parser.fromClause.length == 1);
	assert(parser.fromClause[0].entity.name == "User");
	assert(parser.fromClause[0].entityAlias == "a");
	assert(parser.selectClause.length == 1);
	assert(parser.selectClause[0].prop is null);
	assert(parser.selectClause[0].aliasPtr.entity.name == "User");
	assert(parser.orderByClause.length == 2);
	assert(parser.orderByClause[0].prop.propertyName == "name");
	assert(parser.orderByClause[0].aliasPtr.entity.name == "User");
	assert(parser.orderByClause[0].asc == true);
	assert(parser.orderByClause[1].prop.propertyName == "flags");
	assert(parser.orderByClause[1].aliasPtr.entity.name == "User");
	assert(parser.orderByClause[1].asc == false);
}
