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
	Token whereClause; // AST for WHERE expression


	this(EntityMetaData metadata, string query) {
		this.metadata = metadata;
		this.query = query;
		//writeln("query: " ~ query);
		tokens = tokenize(query);
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
		//writeln("FROM alias is " ~ fromClause[0].entityAlias);
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
		whereClause = new Token(TokenType.Expression, tokens, start, end);
		//writeln("before convert fields:\n" ~ whereClause.dump(0));
		convertFields(whereClause.children);
		//writeln("after convert fields:\n" ~ whereClause.dump(0));
		convertIsNullIsNotNull(whereClause.children);
		//writeln("converting WHERE expression\n" ~ whereClause.dump(0));
		convertUnaryPlusMinus(whereClause.children);
		foldBraces(whereClause.children);
		foldOperators(whereClause.children);
		dropBraces(whereClause.children);
		//writeln("after conversion:\n" ~ whereClause.dump(0));
	}

	static void foldBraces(ref Token[] items) {
		while (true) {
			if (items.length == 0)
				return;
			int lastOpen = -1;
			int firstClose = -1;
			for (int i=0; i<items.length; i++) {
				if (items[i].type == TokenType.OpenBracket) {
					lastOpen = i;
				} if (items[i].type == TokenType.CloseBracket) {
					firstClose = i;
					break;
				}
			}
			if (lastOpen == -1 && firstClose == -1)
				return;
			//writeln("folding braces " ~ to!string(lastOpen) ~ " .. " ~ to!string(firstClose));
			enforceEx!SyntaxError(lastOpen >= 0 && lastOpen < firstClose, "Unpaired braces in WHERE clause");
			Token folded = new Token(TokenType.Braces, items, lastOpen + 1, firstClose);
//			size_t oldlen = items.length;
//			int removed = firstClose - lastOpen;
			replaceInPlace(items, lastOpen, firstClose + 1, [folded]);
//			assert(items.length == oldlen - removed);
			foldBraces(folded.children);
		}
	}

	static void dropBraces(ref Token[] items) {
		foreach (t; items) {
			if (t.children.length > 0)
				dropBraces(t.children);
		}
		for (int i=0; i<items.length; i++) {
			if (items[i].type != TokenType.Braces)
				continue;
			if (items[i].children.length == 1) {
				Token t = items[i].children[0];
				replaceInPlace(items, i, i + 1, [t]);
			}
		}
	}

	void convertIsNullIsNotNull(ref Token[] items) {
		for (int i=items.length - 2; i >= 0; i--) {
			if (items[i].type != TokenType.Operator || items[i + 1].type != TokenType.Keyword)
				continue;
			if (items[i].operator == OperatorType.IS && items[i + 1].keyword == KeywordType.NULL) {
				Token folded = new Token(OperatorType.IS_NULL, "IS NULL");
				replaceInPlace(items, i, i + 2, [folded]);
				i-=2;
			}
		}
		for (int i=items.length - 3; i >= 0; i--) {
			if (items[i].type != TokenType.Operator || items[i + 1].type != TokenType.Operator || items[i + 2].type != TokenType.Keyword)
				continue;
			if (items[i].operator == OperatorType.IS && items[i + 1].operator == OperatorType.NOT && items[i + 2].keyword == KeywordType.NULL) {
				Token folded = new Token(OperatorType.IS_NOT_NULL, "IS NOT NULL");
				replaceInPlace(items, i, i + 3, [folded]);
				i-=3;
			}
		}
	}

	void convertFields(ref Token[] items) {
		while(true) {
			int p = -1;
			for (int i=0; i<items.length; i++) {
				if (items[i].type != TokenType.Ident && items[i].type != TokenType.Alias)
					continue;
				p = i;
				break;
			}
			if (p == -1)
				return;
			// found identifier at position p
			string[] idents;
			int lastp = p;
			idents ~= items[p].text;
			for (int i=p + 1; i < items.length - 1; i+=2) {
				if (items[i].type != TokenType.Dot)
					break;
				enforceEx!SyntaxError(i < items.length - 1 && items[i + 1].type == TokenType.Ident, "Syntax error in WHERE condition - no property name after . for " ~ items[p].toString());
				lastp = i;
				idents ~= items[i + 1].text;
			}
			string aliasName;
			string propertyName;
			string fullName;
			if (idents.length == 1) {
				aliasName = fromClause[0].entityAlias;
				enforceEx!SyntaxError(items[p].type != TokenType.Alias, "Syntax error in WHERE condition - unexpected alias " ~ aliasName);
				propertyName = idents[0];
			} else if (idents.length == 2) {
				aliasName = idents[0];
				propertyName = idents[1];
				enforceEx!SyntaxError(items[p].type == TokenType.Alias, "Syntax error in WHERE condition - unknown alias " ~ aliasName);
			} else {
				enforceEx!SyntaxError(false, "Only one and two levels {property} and {entityAlias.property} supported for property reference in current version");
			}
			fullName = aliasName ~ "." ~ propertyName;
			//writeln("full name = " ~ fullName);
			FromClauseItem * a = findFromClauseByAlias(aliasName);
			EntityInfo ei = a.entity;
			PropertyInfo pi = ei.findProperty(propertyName);
			Token t = new Token(TokenType.Field, fullName);
			t.entity = ei;
			t.field = pi;
			replaceInPlace(items, p, lastp + 1, [t]);
		}
	}

	static void convertUnaryPlusMinus(ref Token[] items) {
		foreach (t; items) {
			if (t.children.length > 0)
				convertUnaryPlusMinus(t.children);
		}
		for (int i=0; i<items.length; i++) {
			if (items[i].type != TokenType.Operator)
				continue;
			OperatorType op = items[i].operator;
			if (op == OperatorType.ADD || op == OperatorType.SUB) {
				// convert + and - to unary form if necessary
				if (i == 0 || !items[i - 1].isExpression()) {
					items[i].operator = (op == OperatorType.ADD) ? OperatorType.UNARY_PLUS : OperatorType.UNARY_MINUS;
				}
			}
		}
	}

	static void foldOperators(ref Token[] items) {
		foreach (t; items) {
			if (t.children.length > 0)
				foldOperators(t.children);
		}
		while (true) {
			//
			int bestOpPosition = -1;
			int bestOpPrecedency = -1;
			OperatorType t = OperatorType.NONE;
			for (int i=0; i<items.length; i++) {
				if (items[i].type != TokenType.Operator)
					continue;
				int p = operatorPrecedency(items[i].operator);
				if (p > bestOpPrecedency) {
					bestOpPrecedency = p;
					bestOpPosition = i;
					t = items[i].operator;
				}
			}
			if (bestOpPrecedency == -1)
				return;
			//writeln("Found op " ~ items[bestOpPosition].toString() ~ " at position " ~ to!string(bestOpPosition) ~ " with priority " ~ to!string(bestOpPrecedency));
			if (t == OperatorType.NOT || t == OperatorType.UNARY_PLUS || t == OperatorType.UNARY_MINUS) {
				// fold unary
				enforceEx!SyntaxError(bestOpPosition < items.length && items[bestOpPosition + 1].isExpression(), "Syntax error in WHERE condition " ~ items[bestOpPosition].toString());
				Token folded = new Token(t, items[bestOpPosition].text, items[bestOpPosition + 1]);
				replaceInPlace(items, bestOpPosition, bestOpPosition + 2, [folded]);
			} else if (t == OperatorType.IS_NULL || t == OperatorType.IS_NOT_NULL) {
				// fold unary
				enforceEx!SyntaxError(bestOpPosition > 0 && items[bestOpPosition - 1].isExpression(), "Syntax error in WHERE condition " ~ items[bestOpPosition].toString());
				Token folded = new Token(t, items[bestOpPosition].text, items[bestOpPosition - 1]);
				replaceInPlace(items, bestOpPosition - 1, bestOpPosition + 1, [folded]);
			} else if (t == OperatorType.BETWEEN) {
				// fold  X BETWEEN A AND B
				enforceEx!SyntaxError(bestOpPosition > 0, "Syntax error in WHERE condition - no left arg for BETWEEN operator");
				enforceEx!SyntaxError(bestOpPosition < items.length - 1, "Syntax error in WHERE condition - no min bound for BETWEEN operator");
				enforceEx!SyntaxError(bestOpPosition < items.length - 3, "Syntax error in WHERE condition - no max bound for BETWEEN operator");
				enforceEx!SyntaxError(items[bestOpPosition + 2].operator == OperatorType.AND, "Syntax error in WHERE condition - no max bound for BETWEEN operator");
				Token folded = new Token(t, items[bestOpPosition].text, items[bestOpPosition - 1]);
				folded.children ~= items[bestOpPosition + 1];
				folded.children ~= items[bestOpPosition + 3];
				replaceInPlace(items, bestOpPosition - 1, bestOpPosition + 4, [folded]);
			} else {
				// fold binary
				enforceEx!SyntaxError(bestOpPosition > 0, "Syntax error in WHERE condition - no left arg for binary operator " ~ items[bestOpPosition].toString());
				enforceEx!SyntaxError(bestOpPosition < items.length - 1, "Syntax error in WHERE condition - no right arg for binary operator " ~ items[bestOpPosition].toString());
				//writeln("binary op " ~ items[bestOpPosition - 1].toString() ~ " " ~ items[bestOpPosition].toString() ~ " " ~ items[bestOpPosition + 1].toString());
				enforceEx!SyntaxError(items[bestOpPosition - 1].isExpression(), "Syntax error in WHERE condition - wrong type of left arg for binary operator " ~ items[bestOpPosition].toString());
				enforceEx!SyntaxError(items[bestOpPosition - 1].isExpression(), "Syntax error in WHERE condition - wrong type of right arg for binary operator " ~ items[bestOpPosition].toString());
				Token folded = new Token(t, items[bestOpPosition].text, items[bestOpPosition - 1], items[bestOpPosition + 1]);
				replaceInPlace(items, bestOpPosition - 1, bestOpPosition + 2, [folded]);
			}
		}
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
	AS,
	LIKE,
	IN,
	IS,
	NOT,
	NULL,
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

	// symbolic
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

	// from keywords
	LIKE,
	IN,
	IS,
	NOT,
	AND,
	OR,
	BETWEEN,
	IDIV,
	MOD,

	UNARY_PLUS,
	UNARY_MINUS,

	IS_NULL,
	IS_NOT_NULL,
}

OperatorType isOperator(KeywordType t) {
	switch (t) {
		case KeywordType.LIKE: return OperatorType.LIKE;
		case KeywordType.IN: return OperatorType.IN;
		case KeywordType.IS: return OperatorType.IS;
		case KeywordType.NOT: return OperatorType.NOT;
		case KeywordType.AND: return OperatorType.AND;
		case KeywordType.OR: return OperatorType.OR;
		case KeywordType.BETWEEN: return OperatorType.BETWEEN;
		case KeywordType.DIV: return OperatorType.IDIV;
		case KeywordType.MOD: return OperatorType.MOD;
		default: return OperatorType.NONE;
	}
}

int operatorPrecedency(OperatorType t) {
	switch(t) {
		case OperatorType.EQ: return 5; // ==
		case OperatorType.NE: return 5; // != <>
		case OperatorType.LT: return 5; // <
		case OperatorType.GT: return 5; // >
		case OperatorType.LE: return 5; // <=
		case OperatorType.GE: return 5; // >=
		case OperatorType.MUL: return 10; // *
		case OperatorType.ADD: return 9; // +
		case OperatorType.SUB: return 9; // -
		case OperatorType.DIV: return 10; // /
		// from keywords
		case OperatorType.LIKE: return 11;
		case OperatorType.IN: return 12;
		case OperatorType.IS: return 13;
		case OperatorType.NOT: return 6; // ???
		case OperatorType.AND: return 4;
		case OperatorType.OR:  return 3;
		case OperatorType.BETWEEN: return 7; // ???
		case OperatorType.IDIV: return 10;
		case OperatorType.MOD: return 10;
		case OperatorType.UNARY_PLUS: return 15;
		case OperatorType.UNARY_MINUS: return 15;
		case OperatorType.IS_NULL: return 15;
		case OperatorType.IS_NOT_NULL: return 15;
		default: return -1;
	}
}

OperatorType isOperator(string s, ref int i) {
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
	Comma,        // ,
	Entity,       // entity name
	Field,        // field name of some entity
	Alias,        // alias name of some entity
	Parameter,    // ident after :
	// types of compound AST nodes
	Expression,   // any expression
	Braces,       // ( tokens )
	CommaDelimitedList, // tokens, ... , tokens
	OpExpr, // operator expression; current token == operator, children = params
}

class Token {
	TokenType type;
	KeywordType keyword = KeywordType.NONE;
	OperatorType operator = OperatorType.NONE;
	string text;
	string spaceAfter;
	EntityInfo entity;
	PropertyInfo field;
	Token[] children;
	this(TokenType type, string text) {
		this.type = type;
		this.text = text;
	}
	this(KeywordType keyword, string text) {
		this.type = TokenType.Keyword;
		this.keyword = keyword;
		this.text = text;
	}
	this(OperatorType op, string text) {
		this.type = TokenType.Operator;
		this.operator = op;
		this.text = text;
	}
	this(TokenType type, Token[] base, int start, int end) {
		this.type = type;
		this.children = new Token[end - start];
		for (int i = start; i < end; i++)
			children[i - start] = base[i];
	}
	// unary operator expression
	this(OperatorType type, string text, Token right) {
		this.type = TokenType.OpExpr;
		this.operator = type;
		this.text = text;
		this.children = new Token[1];
		this.children[0] = right;
	}
	// binary operator expression
	this(OperatorType type, string text, Token left, Token right) {
		this.type = TokenType.OpExpr;
		this.text = text;
		this.operator = type;
		this.children = new Token[2];
		this.children[0] = left;
		this.children[1] = right;
	}
	bool isExpression() {
		return type==TokenType.Expression || type==TokenType.Braces || type==TokenType.OpExpr || type==TokenType.Parameter 
			|| type==TokenType.Field || type==TokenType.String || type==TokenType.Number;
	}
	bool isCompound() {
		return this.type >= TokenType.Expression;
	}
	string dump(int level) {
		string res;
		for (int i=0; i<level; i++)
			res ~= "    ";
		res ~= toString() ~ "\n";
		foreach (c; children)
			res ~= c.dump(level + 1);
		return res;
	}
	override string toString() {
		switch (type) {
			case TokenType.Keyword:      // WHERE
			case TokenType.Ident: return "id:" ~ text;        // ident
			case TokenType.Number: return "n:" ~ text;       // 25   13.5e-10
			case TokenType.String: return "s:'" ~ text ~ "'";       // 'string'
			case TokenType.Operator: return "op:" ~ text;     // == != <= >= < > + - * /
			case TokenType.Dot: return ".";          // .
			case TokenType.OpenBracket: return "(";  // (
			case TokenType.CloseBracket: return ")"; // )
			case TokenType.Comma: return ".";        // ,
			case TokenType.Entity: return "e:" ~ entity.name;       // entity name
			case TokenType.Field: return "f:" ~ field.propertyName;        // field name of some entity
			case TokenType.Alias: return "a:" ~ text;        // alias name of some entity
			case TokenType.Parameter: return "p:" ~ text;    // ident after :
				// types of compound AST nodes
			case TokenType.Expression: return "expr";   // any expression
			case TokenType.Braces: return "()";       // ( tokens )
			case TokenType.CommaDelimitedList: return ",,,"; // tokens, ... , tokens
			case TokenType.OpExpr: return "" ~ text;
			default: return "UNKNOWN";
		}
	}
	
}

Token[] tokenize(string s) {
	Token[] res;
	int startpos = 0;
	int state = 0;
	int len = cast(int)s.length;
	for (int i=0; i<len; i++) {
		char ch = s[i];
		char ch2 = i < len - 1 ? s[i + 1] : 0;
		char ch3 = i < len - 2 ? s[i + 2] : 0;
		string text;
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
			if (keywordId != KeywordType.NONE && !quotedIdent) {
				OperatorType keywordOp = isOperator(keywordId);
				if (keywordOp != OperatorType.NONE)
					res ~= new Token(keywordOp, text); // operator keyword
				else
					res ~= new Token(keywordId, text);
			} else
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
	QueryParser parser = new QueryParser(schema, "SELECT a FROM User AS a WHERE id = :Id AND name != :skipName OR name IS NULL  AND a.flags IS NOT NULL ORDER BY name, a.flags DESC");
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

	parser = new QueryParser(schema, "SELECT a FROM User AS a WHERE ((id = :Id) OR (name LIKE 'a%' AND flags = (-5 + 7))) AND name != :skipName AND flags BETWEEN 2*2 AND 42/5 ORDER BY name, a.flags DESC");
	assert(parser.whereClause !is null);
	writeln(parser.whereClause.dump(0));

}
