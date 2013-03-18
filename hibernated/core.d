module hibernated.core;

import std.ascii;
import std.exception;
import std.string;

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

class Query {
	EntityMetaData metadata;
	Token[] tokens;
	this(EntityMetaData metadata, string query) {
		this.metadata = metadata;
		tokens = tokenize(query.dup);
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
	return KeywordType.NONE;
}

unittest {
	assert(isKeyword("Null") == KeywordType.NULL);
	assert(isKeyword("from") == KeywordType.FROM);
	assert(isKeyword("SELECT") == KeywordType.SELECT);
	assert(isKeyword("blabla") == KeywordType.NONE);
}

enum TokenType {
	Keyword,
	Ident,
	Number,
	String,
	Dot,
	OpenBracket,
	CloseBracket,
}

class Token {
	TokenType type;
	KeywordType keyword;
	char[] text;
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
		if (isAlpha(ch) || ch=='_' || quotedIdent) {
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
			for(int j=i; j<len; j++) {
				if (isWhite(s[j])) {
					text ~= s[j];
					i = j;
				} else {
					break;
				}
			}
			// don't add whitespace to lexer results
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
			res ~= new Token(TokenType.String, text);
		} else if (isDigit(ch)) {
			// number
			for(int j=i; j<len; j++) {
				if (isDigit(s[j])) {
					text ~= s[j];
					i = j;
				} else {
					break;
				}
			}
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
		}
	}
	return res;
}


