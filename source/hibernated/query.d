/**
 * HibernateD - Object-Relation Mapping for D programming language, with interface similar to Hibernate. 
 * 
 * Hibernate documentation can be found here:
 * $(LINK http://hibernate.org/docs)$(BR)
 * 
 * Source file hibernated/core.d.
 *
 * This module contains HQL query parser and HQL to SQL transform implementation.
 * 
 * Copyright: Copyright 2013
 * License:   $(LINK www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Author:   Vadim Lopatin
 */
module hibernated.query;

import std.ascii;
import std.algorithm;
import std.exception;
import std.array;
import std.string;
import std.conv;
import std.stdio;
import std.variant;

import ddbc.core;

import hibernated.annotations;
import hibernated.metadata;
import hibernated.type;
import hibernated.core;
import hibernated.dialect;
import hibernated.dialects.mysqldialect;


// For backwards compatibily
// 'enforceEx' will be removed with 2.089
static if(__VERSION__ < 2080) {
    alias enforceHelper = enforceEx;
} else {
    alias enforceHelper = enforce;
}

enum JoinType {
    InnerJoin,
    LeftJoin,
}

class FromClauseItem {
	string entityName;
    const EntityInfo entity;
	string entityAlias;
	string sqlAlias;
    int startColumn;
    int selectedColumns;
    // for JOINs
    JoinType joinType = JoinType.InnerJoin;
    bool fetch;
    FromClauseItem base;
    const PropertyInfo baseProperty;
    string pathString;
    int index;
    int selectIndex;

    string getFullPath() {
        if (base is null)
            return entityAlias;
        return base.getFullPath() ~ "." ~ baseProperty.propertyName;
    }

    this(const EntityInfo entity, string entityAlias, JoinType joinType, bool fetch, FromClauseItem base = null, const PropertyInfo baseProperty = null) {
        this.entityName = entity.name;
        this.entity = entity;
        this.joinType = joinType;
        this.fetch = fetch;
        this.base = base;
        this.baseProperty = baseProperty;
        this.selectIndex = -1;
    }

}

class FromClause {
    FromClauseItem[] items;
    FromClauseItem add(const EntityInfo entity, string entityAlias, JoinType joinType, bool fetch, FromClauseItem base = null, const PropertyInfo baseProperty = null) {
        FromClauseItem item = new FromClauseItem(entity, entityAlias, joinType, fetch, base, baseProperty);
        item.entityAlias = entityAlias is null ? "_a" ~ to!string(items.length + 1) : entityAlias;
        item.sqlAlias = "_t" ~ to!string(items.length + 1);
        item.index = cast(int)items.length;
        item.pathString = item.getFullPath();
        items ~= item;
        return item;
    }
    @property size_t length() { return items.length; }
    string getSQL() {
        return "";
    }
    @property FromClauseItem first() {
        return items[0];
    }
    FromClauseItem opIndex(int index) {
        enforceHelper!HibernatedException(index >= 0 && index < items.length, "FromClause index out of range: " ~ to!string(index));
        return items[index];
    }
    FromClauseItem opIndex(string aliasName) {
        return findByAlias(aliasName);
    }
    bool hasAlias(string aliasName) {
        foreach(ref m; items) {
            if (m.entityAlias == aliasName)
                return true;
        }
        return false;
    }
    FromClauseItem findByAlias(string aliasName) {
        foreach(ref m; items) {
            if (m.entityAlias == aliasName)
                return m;
        }
        throw new QuerySyntaxException("Cannot find FROM alias by name " ~ aliasName);
    }
    FromClauseItem findByPath(string path) {
        foreach(ref m; items) {
            if (m.pathString == path)
                return m;
        }
        return null;
    }
}

struct OrderByClauseItem {
	FromClauseItem from;
	PropertyInfo prop;
	bool asc;
}

struct SelectClauseItem {
	FromClauseItem from;
	PropertyInfo prop;
}

class QueryParser {
	string query;
	EntityMetaData metadata;
	Token[] tokens;
    FromClause fromClause;
	//FromClauseItem[] fromClause;
	string[] parameterNames;
	OrderByClauseItem[] orderByClause;
	SelectClauseItem[] selectClause;
	Token whereClause; // AST for WHERE expression
	
	
	this(EntityMetaData metadata, string query) {
		this.metadata = metadata;
		this.query = query;
        fromClause = new FromClause();
		//writeln("tokenizing query: " ~ query);
		tokens = tokenize(query);
        //writeln("parsing query: " ~ query);
        parse();
        //writeln("parsing done");
    }
	
	void parse() {
		processParameterNames(0, cast(int)tokens.length); // replace pairs {: Ident} with single Parameter token
		int len = cast(int)tokens.length;
		//writeln("Query tokens: " ~ to!string(len));
		int fromPos = findKeyword(KeywordType.FROM);
		int selectPos = findKeyword(KeywordType.SELECT);
		int wherePos = findKeyword(KeywordType.WHERE);
		int orderPos = findKeyword(KeywordType.ORDER);
		enforceHelper!QuerySyntaxException(fromPos >= 0, "No FROM clause in query " ~ query);
		enforceHelper!QuerySyntaxException(selectPos <= 0, "SELECT clause should be first - invalid query " ~ query);
		enforceHelper!QuerySyntaxException(wherePos == -1 || wherePos > fromPos, "Invalid WHERE position in query " ~ query);
		enforceHelper!QuerySyntaxException(orderPos == -1 || (orderPos < tokens.length - 2 && tokens[orderPos + 1].keyword == KeywordType.BY), "Invalid ORDER BY in query " ~ query);
		enforceHelper!QuerySyntaxException(orderPos == -1 || orderPos > fromPos, "Invalid ORDER BY position in query " ~ query);
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
		else
			defaultSelectClause();
		bool selectedEntities = validateSelectClause();
		if (wherePos >= 0 && whereEnd > wherePos)
			parseWhereClause(wherePos + 1, whereEnd);
		if (orderPos >= 0 && orderEnd > orderPos)
			parseOrderClause(orderPos + 2, orderEnd);
        if (selectedEntities) {
            processAutoFetchReferences();
            prepareSelectFields();
        }
	}
	
    private void prepareSelectFields() {
        int startColumn = 1;
        for (int i=0; i < fromClause.length; i++) {
            FromClauseItem item = fromClause[i];
            if (!item.fetch)
                continue;
            int count = item.entity.metadata.getFieldCount(item.entity, false);
            if (count > 0) {
                item.startColumn = startColumn;
                item.selectedColumns = count;
                startColumn += count;
            }
        }
    }

    private void processAutoFetchReferences() {
        FromClauseItem a = selectClause[0].from;
        a.fetch = true;
        processAutoFetchReferences(a);
    }

    private FromClauseItem ensureItemFetched(FromClauseItem a, const PropertyInfo p) {
        FromClauseItem res;
        string path = a.pathString ~ "." ~ p.propertyName;
        //writeln("ensureItemFetched " ~ path);
        res = fromClause.findByPath(path);
        if (res is null) {
            // autoadd join
            assert(p.referencedEntity !is null);
            res = fromClause.add(p.referencedEntity, null, p.nullable ? JoinType.LeftJoin : JoinType.InnerJoin, true, a, p);
        } else {
            // force fetch
            res.fetch = true;
        }
        bool selectFound = false;
        foreach(s; selectClause) {
            if (s.from == res) {
                selectFound = true;
                break;
            }
        }
        if (!selectFound) {
            SelectClauseItem item;
            item.from = res;
            item.prop = null;
            selectClause ~= item;
        }
        return res;
    }

    private bool isBackReferenceProperty(FromClauseItem a, const PropertyInfo p) {
        if (a.base is null)
            return false;
        auto baseEntity = a.base.entity;
        assert(baseEntity !is null);
        if (p.referencedEntity != baseEntity)
            return false;

        if (p.referencedProperty !is null && p.referencedProperty == a.baseProperty)
            return true;
        if (a.baseProperty.referencedProperty !is null && p == a.baseProperty.referencedProperty)
            return true;
        return false;
    }

    private void processAutoFetchReferences(FromClauseItem a) {
        foreach (p; a.entity.properties) {
            if (p.lazyLoad)
                continue;
            if (p.oneToOne && !isBackReferenceProperty(a, p)) {
                FromClauseItem res = ensureItemFetched(a, p);
                processAutoFetchReferences(res);
            }
        }
    }
    
    private void updateEntity(const EntityInfo entity, string name) {
		foreach(t; tokens) {
			if (t.type == TokenType.Ident && t.text == name) {
                t.entity = cast(EntityInfo)entity;
				t.type = TokenType.Entity;
			}
		}
	}
	
	private void updateAlias(const EntityInfo entity, string name) {
		foreach(t; tokens) {
			if (t.type == TokenType.Ident && t.text == name) {
                t.entity = cast(EntityInfo)entity;
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
				enforceHelper!QuerySyntaxException(tokens[i].type != TokenType.Comma || i != end - 1, "Invalid comma at end of list" ~ errorContext(tokens[start]));
				int endp = i < end - 1 ? i : end;
				enforceHelper!QuerySyntaxException(endp > p, "Invalid comma delimited list" ~ errorContext(tokens[start]));
				callback(p, endp);
				p = i + 1;
			}
		}
	}

    private int parseFieldRef(int start, int end, ref string[] path) {
        int pos = start;
        while (pos < end) {
            if (tokens[pos].type == TokenType.Ident || tokens[pos].type == TokenType.Alias) {
                enforceHelper!QuerySyntaxException(path.length == 0 || tokens[pos].type != TokenType.Alias, "Alias is allowed only as first item" ~ errorContext(tokens[pos]));
                path ~= tokens[pos].text;
                pos++;
                if (pos == end || tokens[pos].type != TokenType.Dot)
                    return pos;
                if (pos == end - 1 || tokens[pos + 1].type != TokenType.Ident)
                    return pos;
                pos++;
            } else {
                break;
            }
        }
        enforceHelper!QuerySyntaxException(tokens[pos].type != TokenType.Dot, "Unexpected dot at end in field list" ~ errorContext(tokens[pos]));
        enforceHelper!QuerySyntaxException(path.length > 0, "Empty field list" ~ errorContext(tokens[pos]));
        return pos;
    }
	
    private void parseFirstFromClause(int start, int end, out int pos) {
        enforceHelper!QuerySyntaxException(start < end, "Invalid FROM clause " ~ errorContext(tokens[start]));
        // minimal support:
        //    Entity
        //    Entity alias
        //    Entity AS alias
        enforceHelper!QuerySyntaxException(tokens[start].type == TokenType.Ident, "Entity name identifier expected in FROM clause" ~ errorContext(tokens[start]));
        string entityName = cast(string)tokens[start].text;
        auto ei = metadata.findEntity(entityName);
        updateEntity(ei, entityName);
        string aliasName = null;
        int p = start + 1;
        if (p < end && tokens[p].type == TokenType.Keyword && tokens[p].keyword == KeywordType.AS)
            p++;
        if (p < end) {
            enforceHelper!QuerySyntaxException(tokens[p].type == TokenType.Ident, "Alias name identifier expected in FROM clause" ~ errorContext(tokens[p]));
            aliasName = cast(string)tokens[p].text;
            p++;
        }
        if (aliasName != null)
            updateAlias(ei, aliasName);
        fromClause.add(ei, aliasName, JoinType.InnerJoin, false);
        pos = p;
    }

    void appendFromClause(Token context, string[] path, string aliasName, JoinType joinType, bool fetch) {
        int p = 0;
        enforceHelper!QuerySyntaxException(fromClause.hasAlias(path[p]), "Unknown alias " ~ path[p] ~ " in FROM clause" ~ errorContext(context));
        FromClauseItem baseClause = findFromClauseByAlias(path[p]);
        //string pathString = path[p];
        p++;
        while(true) {
            auto baseEntity = baseClause.entity;
            enforceHelper!QuerySyntaxException(p < path.length, "Property name expected in FROM clause" ~ errorContext(context));
            string propertyName = path[p++];
            auto property = baseEntity[propertyName];
            auto referencedEntity = property.referencedEntity;
            assert(referencedEntity !is null);
            enforceHelper!QuerySyntaxException(!property.simple, "Simple property " ~ propertyName ~ " cannot be used in JOIN" ~ errorContext(context));
            enforceHelper!QuerySyntaxException(!property.embedded, "Embedded property " ~ propertyName ~ " cannot be used in JOIN" ~ errorContext(context));
            bool last = (p == path.length);
            FromClauseItem item = fromClause.add(referencedEntity, last ? aliasName : null, joinType, fetch, baseClause, property);
            if (last && aliasName !is null)
                updateAlias(referencedEntity, item.entityAlias);
            baseClause = item;
            if (last)
                break;
        }
    }

    void parseFromClause(int start, int end) {
        int p = start;
        parseFirstFromClause(start, end, p);
        while (p < end) {
            Token context = tokens[p];
            JoinType joinType = JoinType.InnerJoin;
            if (tokens[p].keyword == KeywordType.LEFT) {
                joinType = JoinType.LeftJoin;
                p++;
            } else if (tokens[p].keyword == KeywordType.INNER) {
                p++;
            }
            enforceHelper!QuerySyntaxException(p < end && tokens[p].keyword == KeywordType.JOIN, "Invalid FROM clause" ~ errorContext(tokens[p]));
            p++;
            enforceHelper!QuerySyntaxException(p < end, "Invalid FROM clause - incomplete JOIN" ~ errorContext(tokens[p]));
            bool fetch = false;
            if (tokens[p].keyword == KeywordType.FETCH) {
                fetch = true;
                p++;
                enforceHelper!QuerySyntaxException(p < end, "Invalid FROM clause - incomplete JOIN" ~ errorContext(tokens[p]));
            }
            string[] path;
            p = parseFieldRef(p, end, path);
            string aliasName;
            bool hasAS = false;
            if (p < end && tokens[p].keyword == KeywordType.AS) {
                p++;
                hasAS = true;
            }
            enforceHelper!QuerySyntaxException(p < end && tokens[p].type == TokenType.Ident, "Invalid FROM clause - no alias in JOIN" ~ errorContext(tokens[p]));
            aliasName = tokens[p].text;
            p++;
            appendFromClause(context, path, aliasName, joinType, fetch);
        }
		enforceHelper!QuerySyntaxException(p == end, "Invalid FROM clause" ~ errorContext(tokens[p]));
	}
	
	// in pairs {: Ident} replace type of ident with Parameter 
	void processParameterNames(int start, int end) {
		for (int i = start; i < end; i++) {
			if (tokens[i].type == TokenType.Parameter) {
				parameterNames ~= cast(string)tokens[i].text;
			}
		}
	}
	
	FromClauseItem findFromClauseByAlias(string aliasName) {
        return fromClause.findByAlias(aliasName);
	}
	
	void addSelectClauseItem(string aliasName, string[] propertyNames) {
		//writeln("addSelectClauseItem alias=" ~ aliasName ~ " properties=" ~ to!string(propertyNames));
		FromClauseItem from = aliasName == null ? fromClause.first : findFromClauseByAlias(aliasName);
		SelectClauseItem item;
		item.from = from;
		item.prop = null;
		EntityInfo ei = cast(EntityInfo)from.entity;
		if (propertyNames.length > 0) {
			item.prop = cast(PropertyInfo)ei.findProperty(propertyNames[0]);
			propertyNames.popFront();
			while (item.prop.embedded) {
				//writeln("Embedded property " ~ item.prop.propertyName ~ " of type " ~ item.prop.referencedEntityName);
                ei = cast(EntityInfo)item.prop.referencedEntity;
			    enforceHelper!QuerySyntaxException(propertyNames.length > 0, "@Embedded field property name should be specified when selecting " ~ aliasName ~ "." ~ item.prop.propertyName);
                item.prop = cast(PropertyInfo)ei.findProperty(propertyNames[0]);
				propertyNames.popFront();
			}
		}
		enforceHelper!QuerySyntaxException(propertyNames.length == 0, "Extra field names in SELECT clause in query " ~ query);
		selectClause ~= item;
		//insertInPlace(selectClause, 0, item);
	}
	
	void addOrderByClauseItem(string aliasName, string propertyName, bool asc) {
		FromClauseItem from = aliasName == null ? fromClause.first : findFromClauseByAlias(aliasName);
		OrderByClauseItem item;
		item.from = from;
        item.prop = cast(PropertyInfo)from.entity.findProperty(propertyName);
		item.asc = asc;
		orderByClause ~= item;
		//insertInPlace(orderByClause, 0, item);
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
		enforceHelper!QuerySyntaxException(start < end, "Empty ORDER BY clause item" ~ errorContext(tokens[start]));
		if (start == end - 1) {
			// no alias
			enforceHelper!QuerySyntaxException(tokens[start].type == TokenType.Ident, "Property name expected in ORDER BY clause" ~ errorContext(tokens[start]));
			addOrderByClauseItem(null, cast(string)tokens[start].text, asc);
		} else if (start == end - 3) {
			enforceHelper!QuerySyntaxException(tokens[start].type == TokenType.Alias, "Entity alias expected in ORDER BY clause" ~ errorContext(tokens[start]));
			enforceHelper!QuerySyntaxException(tokens[start + 1].type == TokenType.Dot, "Dot expected after entity alias in ORDER BY clause" ~ errorContext(tokens[start]));
			enforceHelper!QuerySyntaxException(tokens[start + 2].type == TokenType.Ident, "Property name expected after entity alias in ORDER BY clause" ~ errorContext(tokens[start]));
			addOrderByClauseItem(cast(string)tokens[start].text, cast(string)tokens[start + 2].text, asc);
		} else {
			//writeln("range: " ~ to!string(start) ~ " .. " ~ to!string(end));
			enforceHelper!QuerySyntaxException(false, "Invalid ORDER BY clause (expected {property [ASC | DESC]} or {alias.property [ASC | DESC]} )" ~ errorContext(tokens[start]));
		}
	}
	
	void parseSelectClauseItem(int start, int end) {
		// for each comma delimited item
		// in current version it can only be
		// {property}  or  {alias . property}
		//writeln("SELECT ITEM: " ~ to!string(start) ~ " .. " ~ to!string(end));
		enforceHelper!QuerySyntaxException(tokens[start].type == TokenType.Ident || tokens[start].type == TokenType.Alias, "Property name or alias expected in SELECT clause in query " ~ query ~ errorContext(tokens[start]));
		string aliasName;
		int p = start;
		if (tokens[p].type == TokenType.Alias) {
            //writeln("select clause alias: " ~ tokens[p].text ~ " query: " ~ query);
			aliasName = cast(string)tokens[p].text;
			p++;
			enforceHelper!QuerySyntaxException(p == end || tokens[p].type == TokenType.Dot, "SELECT clause item is invalid (only  [alias.]field{[.field2]}+ allowed) " ~ errorContext(tokens[start]));
			if (p < end - 1 && tokens[p].type == TokenType.Dot)
				p++;
		} else {
            //writeln("select clause non-alias: " ~ tokens[p].text ~ " query: " ~ query);
        }
		string[] fieldNames;
		while (p < end && tokens[p].type == TokenType.Ident) {
			fieldNames ~= tokens[p].text;
			p++;
			if (p > end - 1 || tokens[p].type != TokenType.Dot)
				break;
			// skipping dot
			p++;
		}
		//writeln("parseSelectClauseItem pos=" ~ to!string(p) ~ " end=" ~ to!string(end));
		enforceHelper!QuerySyntaxException(p >= end, "SELECT clause item is invalid (only  [alias.]field{[.field2]}+ allowed) " ~ errorContext(tokens[start]));
		addSelectClauseItem(aliasName, fieldNames);
	}
	
	void parseSelectClause(int start, int end) {
		enforceHelper!QuerySyntaxException(start < end, "Invalid SELECT clause" ~ errorContext(tokens[start]));
		splitCommaDelimitedList(start, end, &parseSelectClauseItem);
	}
	
	void defaultSelectClause() {
		addSelectClauseItem(fromClause.first.entityAlias, null);
	}
	
	bool validateSelectClause() {
		enforceHelper!QuerySyntaxException(selectClause != null && selectClause.length > 0, "Invalid SELECT clause");
		int aliasCount = 0;
		int fieldCount = 0;
		foreach(a; selectClause) {
			if (a.prop !is null)
				fieldCount++;
			else
				aliasCount++;
		}
		enforceHelper!QuerySyntaxException((aliasCount == 1 && fieldCount == 0) || (aliasCount == 0 && fieldCount > 0), "You should either use single entity alias or one or more properties in SELECT clause. Don't mix objects with primitive fields");
        return aliasCount > 0;
	}
	
	void parseWhereClause(int start, int end) {
		enforceHelper!QuerySyntaxException(start < end, "Invalid WHERE clause" ~ errorContext(tokens[start]));
		whereClause = new Token(tokens[start].pos, TokenType.Expression, tokens, start, end);
		//writeln("before convert fields:\n" ~ whereClause.dump(0));
		convertFields(whereClause.children);
		//writeln("after convertFields before convertIsNullIsNotNull:\n" ~ whereClause.dump(0));
		convertIsNullIsNotNull(whereClause.children);
		//writeln("after convertIsNullIsNotNull\n" ~ whereClause.dump(0));
		convertUnaryPlusMinus(whereClause.children);
		//writeln("after convertUnaryPlusMinus\n" ~ whereClause.dump(0));
		foldBraces(whereClause.children);
		//writeln("after foldBraces\n" ~ whereClause.dump(0));
		foldOperators(whereClause.children);
		//writeln("after foldOperators\n" ~ whereClause.dump(0));
		dropBraces(whereClause.children);
		//writeln("after dropBraces\n" ~ whereClause.dump(0));
	}
	
	void foldBraces(ref Token[] items) {
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
			enforceHelper!QuerySyntaxException(lastOpen >= 0 && lastOpen < firstClose, "Unpaired braces in WHERE clause" ~ errorContext(tokens[lastOpen]));
			Token folded = new Token(items[lastOpen].pos, TokenType.Braces, items, lastOpen + 1, firstClose);
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
		for (int i = cast(int)items.length - 2; i >= 0; i--) {
			if (items[i].type != TokenType.Operator || items[i + 1].type != TokenType.Keyword)
				continue;
			if (items[i].operator == OperatorType.IS && items[i + 1].keyword == KeywordType.NULL) {
				Token folded = new Token(items[i].pos,OperatorType.IS_NULL, "IS NULL");
				replaceInPlace(items, i, i + 2, [folded]);
				i-=2;
			}
		}
		for (int i = cast(int)items.length - 3; i >= 0; i--) {
			if (items[i].type != TokenType.Operator || items[i + 1].type != TokenType.Operator || items[i + 2].type != TokenType.Keyword)
				continue;
			if (items[i].operator == OperatorType.IS && items[i + 1].operator == OperatorType.NOT && items[i + 2].keyword == KeywordType.NULL) {
				Token folded = new Token(items[i].pos, OperatorType.IS_NOT_NULL, "IS NOT NULL");
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
				enforceHelper!QuerySyntaxException(i < items.length - 1 && items[i + 1].type == TokenType.Ident, "Syntax error in WHERE condition - no property name after . " ~ errorContext(items[p]));
				lastp = i + 1;
				idents ~= items[i + 1].text;
			}
			string fullName;
			FromClauseItem a;
			if (items[p].type == TokenType.Alias) {
				a = findFromClauseByAlias(idents[0]);
				idents.popFront();
			} else {
				// use first FROM clause if alias is not specified
				a = fromClause.first;
			}
			string aliasName = a.entityAlias;
            EntityInfo ei = cast(EntityInfo)a.entity;
			enforceHelper!QuerySyntaxException(idents.length > 0, "Syntax error in WHERE condition - alias w/o property name: " ~ aliasName ~ errorContext(items[p]));
            PropertyInfo pi;
            fullName = aliasName;
            while(true) {
    			string propertyName = idents[0];
    			idents.popFront();
    			fullName ~= "." ~ propertyName;
                pi = cast(PropertyInfo)ei.findProperty(propertyName);
    			while (pi.embedded) { // loop to allow nested @Embedded
    				enforceHelper!QuerySyntaxException(idents.length > 0, "Syntax error in WHERE condition - @Embedded property reference should include reference to @Embeddable property " ~ aliasName ~ errorContext(items[p]));
    				propertyName = idents[0];
    				idents.popFront();
                    pi = cast(PropertyInfo)pi.referencedEntity.findProperty(propertyName);
    				fullName = fullName ~ "." ~ propertyName;
    			}
                if (idents.length == 0)
                    break;
                if (idents.length > 0) {
                    // more field names
                    string pname = idents[0];
                    enforceHelper!QuerySyntaxException(pi.referencedEntity !is null, "Unexpected extra field name " ~ pname ~ " - property " ~ propertyName ~ " doesn't content subproperties " ~ errorContext(items[p]));
                    ei = cast(EntityInfo)pi.referencedEntity;
                    FromClauseItem newClause = fromClause.findByPath(fullName);
                    if (newClause is null) {
                        // autogenerate FROM clause
                        newClause = fromClause.add(ei, null, pi.nullable ? JoinType.LeftJoin : JoinType.InnerJoin, false, a, pi);
                    }
                    a = newClause;
                }
            }
			enforceHelper!QuerySyntaxException(idents.length == 0, "Unexpected extra field name " ~ idents[0] ~ errorContext(items[p]));
			//writeln("full name = " ~ fullName);
			Token t = new Token(items[p].pos, TokenType.Field, fullName);
            t.entity = cast(EntityInfo)ei;
            t.field = cast(PropertyInfo)pi;
			t.from = a;
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
	
	string errorContext(Token token) {
		return " near `" ~ query[token.pos .. $] ~ "` in query `" ~ query ~ "`";
	}

    void foldCommaSeparatedList(Token braces) {
        // fold inside braces
        Token[] items = braces.children;
        int start = 0;
        Token[] list;
        for (int i=0; i <= items.length; i++) {
            if (i == items.length || items[i].type == TokenType.Comma) {
                enforceHelper!QuerySyntaxException(i > start, "Empty item in comma separated list" ~ errorContext(items[i]));
                enforceHelper!QuerySyntaxException(i != items.length - 1, "Empty item in comma separated list" ~ errorContext(items[i]));
                Token item = new Token(items[start].pos, TokenType.Expression, braces.children, start, i);
                foldOperators(item.children);
                enforceHelper!QuerySyntaxException(item.children.length == 1, "Invalid expression in list item" ~ errorContext(items[i]));
                list ~= item.children[0];
                start = i + 1;
            }
        }
        enforceHelper!QuerySyntaxException(list.length > 0, "Empty list" ~ errorContext(items[0]));
        braces.type = TokenType.CommaDelimitedList;
        braces.children = list;
    }

	void foldOperators(ref Token[] items) {
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
				enforceHelper!QuerySyntaxException(bestOpPosition < items.length && items[bestOpPosition + 1].isExpression(), "Syntax error in WHERE condition " ~ errorContext(items[bestOpPosition]));
				Token folded = new Token(items[bestOpPosition].pos, t, items[bestOpPosition].text, items[bestOpPosition + 1]);
				replaceInPlace(items, bestOpPosition, bestOpPosition + 2, [folded]);
			} else if (t == OperatorType.IS_NULL || t == OperatorType.IS_NOT_NULL) {
				// fold unary
				enforceHelper!QuerySyntaxException(bestOpPosition > 0 && items[bestOpPosition - 1].isExpression(), "Syntax error in WHERE condition " ~ errorContext(items[bestOpPosition]));
				Token folded = new Token(items[bestOpPosition - 1].pos, t, items[bestOpPosition].text, items[bestOpPosition - 1]);
				replaceInPlace(items, bestOpPosition - 1, bestOpPosition + 1, [folded]);
			} else if (t == OperatorType.BETWEEN) {
				// fold  X BETWEEN A AND B
				enforceHelper!QuerySyntaxException(bestOpPosition > 0, "Syntax error in WHERE condition - no left arg for BETWEEN operator");
				enforceHelper!QuerySyntaxException(bestOpPosition < items.length - 1, "Syntax error in WHERE condition - no min bound for BETWEEN operator " ~ errorContext(items[bestOpPosition]));
				enforceHelper!QuerySyntaxException(bestOpPosition < items.length - 3, "Syntax error in WHERE condition - no max bound for BETWEEN operator " ~ errorContext(items[bestOpPosition]));
				enforceHelper!QuerySyntaxException(items[bestOpPosition + 2].operator == OperatorType.AND, "Syntax error in WHERE condition - no max bound for BETWEEN operator" ~ errorContext(items[bestOpPosition]));
				Token folded = new Token(items[bestOpPosition - 1].pos, t, items[bestOpPosition].text, items[bestOpPosition - 1]);
				folded.children ~= items[bestOpPosition + 1];
				folded.children ~= items[bestOpPosition + 3];
				replaceInPlace(items, bestOpPosition - 1, bestOpPosition + 4, [folded]);
            } else if (t == OperatorType.IN) {
                // fold  X IN (A, B, ...)
                enforceHelper!QuerySyntaxException(bestOpPosition > 0, "Syntax error in WHERE condition - no left arg for IN operator");
                enforceHelper!QuerySyntaxException(bestOpPosition < items.length - 1, "Syntax error in WHERE condition - no value list for IN operator " ~ errorContext(items[bestOpPosition]));
                enforceHelper!QuerySyntaxException(items[bestOpPosition + 1].type == TokenType.Braces, "Syntax error in WHERE condition - no value list in braces for IN operator" ~ errorContext(items[bestOpPosition]));
                Token folded = new Token(items[bestOpPosition - 1].pos, t, items[bestOpPosition].text, items[bestOpPosition - 1]);
                folded.children ~= items[bestOpPosition + 1];
                foldCommaSeparatedList(items[bestOpPosition + 1]);
                replaceInPlace(items, bestOpPosition - 1, bestOpPosition + 2, [folded]);
                // fold value list
                //writeln("IN operator found: " ~ folded.dump(3));
            } else {
				// fold binary
				enforceHelper!QuerySyntaxException(bestOpPosition > 0, "Syntax error in WHERE condition - no left arg for binary operator " ~ errorContext(items[bestOpPosition]));
				enforceHelper!QuerySyntaxException(bestOpPosition < items.length - 1, "Syntax error in WHERE condition - no right arg for binary operator " ~ errorContext(items[bestOpPosition]));
				//writeln("binary op " ~ items[bestOpPosition - 1].toString() ~ " " ~ items[bestOpPosition].toString() ~ " " ~ items[bestOpPosition + 1].toString());
				enforceHelper!QuerySyntaxException(items[bestOpPosition - 1].isExpression(), "Syntax error in WHERE condition - wrong type of left arg for binary operator " ~ errorContext(items[bestOpPosition]));
				enforceHelper!QuerySyntaxException(items[bestOpPosition + 1].isExpression(), "Syntax error in WHERE condition - wrong type of right arg for binary operator " ~ errorContext(items[bestOpPosition]));
				Token folded = new Token(items[bestOpPosition - 1].pos, t, items[bestOpPosition].text, items[bestOpPosition - 1], items[bestOpPosition + 1]);
				auto oldlen = items.length;
				replaceInPlace(items, bestOpPosition - 1, bestOpPosition + 2, [folded]);
				assert(items.length == oldlen - 2);
			}
		}
	}
	
	void parseOrderClause(int start, int end) {
		enforceHelper!QuerySyntaxException(start < end, "Invalid ORDER BY clause" ~ errorContext(tokens[start]));
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
	
    int addSelectSQL(Dialect dialect, ParsedQuery res, string tableName, bool first, const EntityInfo ei) {
        int colCount = 0;
        for(int j = 0; j < ei.getPropertyCount(); j++) {
            PropertyInfo f = cast(PropertyInfo)ei.getProperty(j);
            string fieldName = f.columnName;
            if (f.embedded) {
                // put embedded cols here
                colCount += addSelectSQL(dialect, res, tableName, first && colCount == 0, f.referencedEntity);
                continue;
            } else if (f.oneToOne) {
            } else {
            }
            if (fieldName is null)
                continue;
            if (!first || colCount > 0) {
                res.appendSQL(", ");
            } else
                first = false;
            
            res.appendSQL(tableName ~ "." ~ dialect.quoteIfNeeded(fieldName));
            colCount++;
        }
        return colCount;
    }

	void addSelectSQL(Dialect dialect, ParsedQuery res) {
		res.appendSQL("SELECT ");
		bool first = true;
		assert(selectClause.length > 0);
		int colCount = 0;
        foreach(i, s; selectClause) {
            s.from.selectIndex = cast(int)i;
        }
		if (selectClause[0].prop is null) {
			// object alias is specified: add all properties of object
            //writeln("selected entity count: " ~ to!string(selectClause.length));
            res.setEntity(selectClause[0].from.entity);
            for(int i = 0; i < fromClause.length; i++) {
                FromClauseItem from = fromClause[i];
                if (!from.fetch)
                    continue;
                string tableName = from.sqlAlias;
    			assert(from !is null);
    			assert(from.entity !is null);
                colCount += addSelectSQL(dialect, res, tableName, colCount == 0, from.entity);
            }
		} else {
			// individual fields specified
			res.setEntity(null);
			foreach(a; selectClause) {
				string fieldName = a.prop.columnName;
				string tableName = a.from.sqlAlias;
				if (!first) {
					res.appendSQL(", ");
				} else
					first = false;
				res.appendSQL(tableName ~ "." ~ dialect.quoteIfNeeded(fieldName));
				colCount++;
			}
		}
		res.setColCount(colCount);
        res.setSelect(selectClause);
	}
	
	void addFromSQL(Dialect dialect, ParsedQuery res) {
        res.setFromClause(fromClause);
		res.appendSpace();
		res.appendSQL("FROM ");
		res.appendSQL(dialect.quoteIfNeeded(fromClause.first.entity.tableName) ~ " AS " ~ fromClause.first.sqlAlias);
        for (int i = 1; i < fromClause.length; i++) {
            FromClauseItem join = fromClause[i];
            FromClauseItem base = join.base;
            assert(join !is null && base !is null);
            res.appendSpace();

            assert(join.baseProperty !is null);
            if (join.baseProperty.manyToMany) {
                string joinTableAlias = base.sqlAlias ~ join.sqlAlias;
                res.appendSQL(join.joinType == JoinType.LeftJoin ? "LEFT JOIN " : "INNER JOIN ");

                res.appendSQL(dialect.quoteIfNeeded(join.baseProperty.joinTable.tableName) ~ " AS " ~ joinTableAlias);
                res.appendSQL(" ON ");
                res.appendSQL(base.sqlAlias);
                res.appendSQL(".");
                res.appendSQL(dialect.quoteIfNeeded(base.entity.getKeyProperty().columnName));
                res.appendSQL("=");
                res.appendSQL(joinTableAlias);
                res.appendSQL(".");
                res.appendSQL(dialect.quoteIfNeeded(join.baseProperty.joinTable.column1));

                res.appendSpace();

                res.appendSQL(join.joinType == JoinType.LeftJoin ? "LEFT JOIN " : "INNER JOIN ");
                res.appendSQL(dialect.quoteIfNeeded(join.entity.tableName) ~ " AS " ~ join.sqlAlias);
                res.appendSQL(" ON ");
                res.appendSQL(joinTableAlias);
                res.appendSQL(".");
                res.appendSQL(dialect.quoteIfNeeded(join.baseProperty.joinTable.column2));
                res.appendSQL("=");
                res.appendSQL(join.sqlAlias);
                res.appendSQL(".");
                res.appendSQL(dialect.quoteIfNeeded(join.entity.getKeyProperty().columnName));
            } else {
                res.appendSQL(join.joinType == JoinType.LeftJoin ? "LEFT JOIN " : "INNER JOIN ");
                res.appendSQL(dialect.quoteIfNeeded(join.entity.tableName) ~ " AS " ~ join.sqlAlias);
                res.appendSQL(" ON ");
                //writeln("adding ON");
                if (join.baseProperty.oneToOne) {
                    assert(join.baseProperty.columnName !is null || join.baseProperty.referencedProperty !is null);
                    if (join.baseProperty.columnName !is null) {
                        //writeln("fk is in base");
                        res.appendSQL(base.sqlAlias);
                        res.appendSQL(".");
                        res.appendSQL(dialect.quoteIfNeeded(join.baseProperty.columnName));
                        res.appendSQL("=");
                        res.appendSQL(join.sqlAlias);
                        res.appendSQL(".");
                        res.appendSQL(dialect.quoteIfNeeded(join.entity.getKeyProperty().columnName));
                    } else {
                        //writeln("fk is in join");
                        res.appendSQL(base.sqlAlias);
                        res.appendSQL(".");
                        res.appendSQL(dialect.quoteIfNeeded(base.entity.getKeyProperty().columnName));
                        res.appendSQL("=");
                        res.appendSQL(join.sqlAlias);
                        res.appendSQL(".");
                        res.appendSQL(dialect.quoteIfNeeded(join.baseProperty.referencedProperty.columnName));
                    }
                } else if (join.baseProperty.manyToOne) {
                    assert(join.baseProperty.columnName !is null, "ManyToOne should have JoinColumn as well");
                    //writeln("fk is in base");
                    res.appendSQL(base.sqlAlias);
                    res.appendSQL(".");
                    res.appendSQL(dialect.quoteIfNeeded(join.baseProperty.columnName));
                    res.appendSQL("=");
                    res.appendSQL(join.sqlAlias);
                    res.appendSQL(".");
                    res.appendSQL(dialect.quoteIfNeeded(join.entity.getKeyProperty().columnName));
                } else if (join.baseProperty.oneToMany) {
                    res.appendSQL(base.sqlAlias);
                    res.appendSQL(".");
                    res.appendSQL(dialect.quoteIfNeeded(base.entity.getKeyProperty().columnName));
                    res.appendSQL("=");
                    res.appendSQL(join.sqlAlias);
                    res.appendSQL(".");
                    res.appendSQL(dialect.quoteIfNeeded(join.baseProperty.referencedProperty.columnName));
                } else {
                    // TODO: support other relations
                    throw new QuerySyntaxException("Invalid relation type in join");
                }
            }
        }
	}
	
	void addWhereCondition(Token t, int basePrecedency, Dialect dialect, ParsedQuery res) {
		if (t.type == TokenType.Expression) {
			addWhereCondition(t.children[0], basePrecedency, dialect, res);
		} else if (t.type == TokenType.Field) {
			string tableName = t.from.sqlAlias;
			string fieldName = t.field.columnName;
			res.appendSpace();
			res.appendSQL(tableName ~ "." ~ dialect.quoteIfNeeded(fieldName));
		} else if (t.type == TokenType.Number) {
			res.appendSpace();
			res.appendSQL(t.text);
		} else if (t.type == TokenType.String) {
			res.appendSpace();
			res.appendSQL(dialect.quoteSqlString(t.text));
		} else if (t.type == TokenType.Parameter) {
			res.appendSpace();
			res.appendSQL("?");
			res.addParam(t.text);
        } else if (t.type == TokenType.CommaDelimitedList) {
            bool first = true;
            for (int i=0; i<t.children.length; i++) {
                if (!first)
                    res.appendSQL(", ");
                else
                    first = false;
                addWhereCondition(t.children[i], 0, dialect, res);
            }
        } else if (t.type == TokenType.OpExpr) {
			int currentPrecedency = operatorPrecedency(t.operator);
			bool needBraces = currentPrecedency < basePrecedency;
			if (needBraces)
				res.appendSQL("(");
			switch(t.operator) {
				case OperatorType.LIKE:
				case OperatorType.EQ:
				case OperatorType.NE:
				case OperatorType.LT:
				case OperatorType.GT:
				case OperatorType.LE:
				case OperatorType.GE:
				case OperatorType.MUL:
				case OperatorType.ADD:
				case OperatorType.SUB:
				case OperatorType.DIV:
				case OperatorType.AND:
				case OperatorType.OR:
				case OperatorType.IDIV:
				case OperatorType.MOD:
					// binary op
					if (!needBraces)
						res.appendSpace();
					addWhereCondition(t.children[0], currentPrecedency, dialect, res);
					res.appendSpace();
					res.appendSQL(t.text);
					res.appendSpace();
					addWhereCondition(t.children[1], currentPrecedency, dialect, res);
					break;
				case OperatorType.UNARY_PLUS:
				case OperatorType.UNARY_MINUS:
				case OperatorType.NOT:
					// unary op
					if (!needBraces)
						res.appendSpace();
					res.appendSQL(t.text);
					res.appendSpace();
					addWhereCondition(t.children[0], currentPrecedency, dialect, res);
					break;
				case OperatorType.IS_NULL:
				case OperatorType.IS_NOT_NULL:
					addWhereCondition(t.children[0], currentPrecedency, dialect, res);
					res.appendSpace();
					res.appendSQL(t.text);
					res.appendSpace();
					break;
				case OperatorType.BETWEEN:
					if (!needBraces)
						res.appendSpace();
					addWhereCondition(t.children[0], currentPrecedency, dialect, res);
					res.appendSQL(" BETWEEN ");
					addWhereCondition(t.children[1], currentPrecedency, dialect, res);
					res.appendSQL(" AND ");
					addWhereCondition(t.children[2], currentPrecedency, dialect, res);
					break;
                case OperatorType.IN:
                    if (!needBraces)
                        res.appendSpace();
                    addWhereCondition(t.children[0], currentPrecedency, dialect, res);
                    res.appendSQL(" IN (");
                    addWhereCondition(t.children[1], currentPrecedency, dialect, res);
                    res.appendSQL(")");
                    break;
				case OperatorType.IS:
				default:
					enforceHelper!QuerySyntaxException(false, "Unexpected operator" ~ errorContext(t));
					break;
			}
			if (needBraces)
				res.appendSQL(")");
		}
	}
	
	void addWhereSQL(Dialect dialect, ParsedQuery res) {
		if (whereClause is null)
			return;
		res.appendSpace();
		res.appendSQL("WHERE ");
		addWhereCondition(whereClause, 0, dialect, res);
	}
	
	void addOrderBySQL(Dialect dialect, ParsedQuery res) {
		if (orderByClause.length == 0)
			return;
		res.appendSpace();
		res.appendSQL("ORDER BY ");
		bool first = true;
		// individual fields specified
		foreach(a; orderByClause) {
			string fieldName = a.prop.columnName;
			string tableName = a.from.sqlAlias;
			if (!first) {
				res.appendSQL(", ");
			} else 
				first = false;
			res.appendSQL(tableName ~ "." ~ dialect.quoteIfNeeded(fieldName));
			if (!a.asc)
				res.appendSQL(" DESC");
		}
	}
	
	ParsedQuery makeSQL(Dialect dialect) {
		ParsedQuery res = new ParsedQuery(query);
		addSelectSQL(dialect, res);
		addFromSQL(dialect, res);
		addWhereSQL(dialect, res);
		addOrderBySQL(dialect, res);
		return res;
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
    FETCH,
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
    if (s=="FETCH") return KeywordType.FETCH;
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
	int pos;
	TokenType type;
	KeywordType keyword = KeywordType.NONE;
	OperatorType operator = OperatorType.NONE;
	string text;
	string spaceAfter;
	EntityInfo entity;
    PropertyInfo field;
	FromClauseItem from;
	Token[] children;
	this(int pos, TokenType type, string text) {
		this.pos = pos;
		this.type = type;
		this.text = text;
	}
	this(int pos, KeywordType keyword, string text) {
		this.pos = pos;
		this.type = TokenType.Keyword;
		this.keyword = keyword;
		this.text = text;
	}
	this(int pos, OperatorType op, string text) {
		this.pos = pos;
		this.type = TokenType.Operator;
		this.operator = op;
		this.text = text;
	}
	this(int pos, TokenType type, Token[] base, int start, int end) {
		this.pos = pos;
		this.type = type;
		this.children = new Token[end - start];
		for (int i = start; i < end; i++)
			children[i - start] = base[i];
	}
	// unary operator expression
	this(int pos, OperatorType type, string text, Token right) {
		this.pos = pos;
		this.type = TokenType.OpExpr;
		this.operator = type;
		this.text = text;
		this.children = new Token[1];
		this.children[0] = right;
	}
	// binary operator expression
	this(int pos, OperatorType type, string text, Token left, Token right) {
		this.pos = pos;
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
			case TokenType.Ident: return "`" ~ text ~ "`";        // ident
			case TokenType.Number: return "" ~ text;       // 25   13.5e-10
			case TokenType.String: return "'" ~ text ~ "'";       // 'string'
			case TokenType.Operator: return "op:" ~ text;     // == != <= >= < > + - * /
			case TokenType.Dot: return ".";          // .
			case TokenType.OpenBracket: return "(";  // (
			case TokenType.CloseBracket: return ")"; // )
			case TokenType.Comma: return ",";        // ,
			case TokenType.Entity: return "entity: " ~ entity.name;       // entity name
			case TokenType.Field: return from.entityAlias ~ "." ~ field.propertyName;        // field name of some entity
			case TokenType.Alias: return "alias: " ~ text;        // alias name of some entity
			case TokenType.Parameter: return ":" ~ text;    // ident after :
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
			res ~= new Token(startpos, op, s[startpos .. i + 1]);
		} else if (ch == ':' && (isAlpha(ch2) || ch2=='_')) {
			// parameter name
			i++;
			// && state == 0
			for(int j=i; j<len; j++) {
				if (isAlphaNum(s[j]) || s[j] == '_') {
					text ~= s[j];
					i = j;
				} else {
					break;
				}
			}
			enforceHelper!QuerySyntaxException(text.length > 0, "Invalid parameter name near " ~ cast(string)s[startpos .. $]);
			res ~= new Token(startpos, TokenType.Parameter, text);
		} else if (isAlpha(ch) || ch=='_' || quotedIdent) {
			// identifier or keyword
			if (quotedIdent) {
				i++;
				enforceHelper!QuerySyntaxException(i < len - 1, "Invalid quoted identifier near " ~ cast(string)s[startpos .. $]);
			}
			// && state == 0
			for(int j=i; j<len; j++) {
				if (isAlphaNum(s[j]) || s[j] == '_') {
					text ~= s[j];
					i = j;
				} else {
					break;
				}
			}
			enforceHelper!QuerySyntaxException(text.length > 0, "Invalid quoted identifier near " ~ cast(string)s[startpos .. $]);
			if (quotedIdent) {
				enforceHelper!QuerySyntaxException(i < len - 1 && s[i + 1] == '`', "Invalid quoted identifier near " ~ cast(string)s[startpos .. $]);
				i++;
			}
			KeywordType keywordId = isKeyword(text);
			if (keywordId != KeywordType.NONE && !quotedIdent) {
				OperatorType keywordOp = isOperator(keywordId);
				if (keywordOp != OperatorType.NONE)
					res ~= new Token(startpos, keywordOp, text); // operator keyword
				else
					res ~= new Token(startpos, keywordId, text);
			} else
				res ~= new Token(startpos, TokenType.Ident, text);
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
			enforceHelper!QuerySyntaxException(i < len - 1 && s[i + 1] == '\'', "Unfinished string near " ~ cast(string)s[startpos .. $]);
			i++;
			res ~= new Token(startpos, TokenType.String, text);
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
			if (i < len - 1 && std.ascii.toLower(s[i + 1]) == 'e') {
				text ~= s[i+1];
				i++;
				if (i < len - 1 && (s[i + 1] == '-' || s[i + 1] == '+')) {
					text ~= s[i+1];
					i++;
				}
				enforceHelper!QuerySyntaxException(i < len - 1 && isDigit(s[i]), "Invalid number near " ~ cast(string)s[startpos .. $]);
				for(int j = i; j<len; j++) {
					if (isDigit(s[j])) {
						text ~= s[j];
						i = j;
					} else {
						break;
					}
				}
			}
			enforceHelper!QuerySyntaxException(i >= len - 1 || !isAlpha(s[i]), "Invalid number near " ~ cast(string)s[startpos .. $]);
			res ~= new Token(startpos, TokenType.Number, text);
		} else if (ch == '.') {
			res ~= new Token(startpos, TokenType.Dot, ".");
		} else if (ch == '(') {
			res ~= new Token(startpos, TokenType.OpenBracket, "(");
		} else if (ch == ')') {
			res ~= new Token(startpos, TokenType.CloseBracket, ")");
		} else if (ch == ',') {
			res ~= new Token(startpos, TokenType.Comma, ",");
		} else {
			enforceHelper!QuerySyntaxException(false, "Invalid character near " ~ cast(string)s[startpos .. $]);
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
}

class ParameterValues {
	Variant[string] values;
	int[][string]params;
	int[string]unboundParams;
	this(int[][string]params) {
		this.params = params;
		foreach(key, value; params) {
			unboundParams[key] = 1;
		}
	}
	void setParameter(string name, Variant value) {
        enforceHelper!QueryParameterException((name in params) !is null, "Attempting to set unknown parameter " ~ name);
		unboundParams.remove(name);
		values[name] = value;
	}
	void checkAllParametersSet() {
		if (unboundParams.length == 0)
			return;
		string list;
		foreach(key, value; unboundParams) {
			if (list.length > 0)
				list ~= ", ";
			list ~= key;
		}
        enforceHelper!QueryParameterException(false, "Parameters " ~ list ~ " not set");
	}
	void applyParams(DataSetWriter ds) {
		foreach(key, indexes; params) {
			Variant value = values[key];
			foreach(i; indexes)
				ds.setVariant(i, value);
		}
	}
}

class ParsedQuery {
	private string _hql;
	private string _sql;
	private int[][string]params; // contains 1-based indexes of ? ? ? placeholders in SQL for param by name
	private int paramIndex = 1;
    private FromClause _from;
    private SelectClauseItem[] _select;
    private EntityInfo _entity;
	private int _colCount = 0;
	this(string hql) {
		_hql = hql;
	}
	@property string hql() { return _hql; }
	@property string sql() { return _sql; }
	@property const(EntityInfo)entity() { return _entity; }
	@property int colCount() { return _colCount; }
    @property FromClause from() { return _from; }
    @property SelectClauseItem[] select() { return _select; }
    void setEntity(const EntityInfo entity) {
        _entity = cast(EntityInfo)entity;
	}
    void setFromClause(FromClause from) {
        _from = from;
    }
    void setSelect(SelectClauseItem[] items) {
        _select = items; 
    }
    void setColCount(int cnt) { _colCount = cnt; }
	void addParam(string paramName) {
		if ((paramName in params) is null) {
			params[paramName] = [paramIndex++];
		} else {
			params[paramName] ~= [paramIndex++];
		}
	}
	int[] getParam(string paramName) {
		if ((paramName in params) is null) {
			throw new HibernatedException("Parameter " ~ paramName ~ " not found in query " ~ _hql);
		} else {
			return params[paramName];
		}
	}
	void appendSQL(string sql) {
		_sql ~= sql;
	}
	void appendSpace() {
		if (_sql.length > 0 && _sql[$ - 1] != ' ')
			_sql ~= ' ';
	}
	ParameterValues createParams() {
		return new ParameterValues(params);
	}
}

unittest {
	ParsedQuery q = new ParsedQuery("FROM User where id = :param1 or id = :param2");
	q.addParam("param1"); // 1
	q.addParam("param2"); // 2
	q.addParam("param1"); // 3
	q.addParam("param1"); // 4
	q.addParam("param3"); // 5
	q.addParam("param2"); // 6
	assert(q.getParam("param1") == [1,3,4]);
	assert(q.getParam("param2") == [2,6]);
	assert(q.getParam("param3") == [5]);
}

unittest {

	//writeln("query unittest");
    import hibernated.tests;

    EntityMetaData schema = new SchemaInfoImpl!(User, Customer, AccountType, Address, Person, MoreInfo, EvenMoreInfo, Role);
	QueryParser parser = new QueryParser(schema, "SELECT a FROM User AS a WHERE id = :Id AND name != :skipName OR name IS NULL  AND a.flags IS NOT NULL ORDER BY name, a.flags DESC");
	assert(parser.parameterNames.length == 2);
	//writeln("param1=" ~ parser.parameterNames[0]);
	//writeln("param2=" ~ parser.parameterNames[1]);
	assert(parser.parameterNames[0] == "Id");
	assert(parser.parameterNames[1] == "skipName");
	assert(parser.fromClause.length == 1);
	assert(parser.fromClause.first.entity.name == "User");
    assert(parser.fromClause.first.entityAlias == "a");
	assert(parser.selectClause.length == 1);
	assert(parser.selectClause[0].prop is null);
	assert(parser.selectClause[0].from.entity.name == "User");
	assert(parser.orderByClause.length == 2);
	assert(parser.orderByClause[0].prop.propertyName == "name");
	assert(parser.orderByClause[0].from.entity.name == "User");
	assert(parser.orderByClause[0].asc == true);
	assert(parser.orderByClause[1].prop.propertyName == "flags");
	assert(parser.orderByClause[1].from.entity.name == "User");
	assert(parser.orderByClause[1].asc == false);
	
	parser = new QueryParser(schema, "SELECT a FROM User AS a WHERE ((id = :Id) OR (name LIKE 'a%' AND flags = (-5 + 7))) AND name != :skipName AND flags BETWEEN 2*2 AND 42/5 ORDER BY name, a.flags DESC");
	assert(parser.whereClause !is null);
	//writeln(parser.whereClause.dump(0));
	Dialect dialect = new MySQLDialect();
	
	assert(dialect.quoteSqlString("abc") == "'abc'");
	assert(dialect.quoteSqlString("a'b'c") == "'a\\'b\\'c'");
	assert(dialect.quoteSqlString("a\nc") == "'a\\nc'");
	
	parser = new QueryParser(schema, "FROM User AS u WHERE id = :Id and u.name like '%test%'");
	ParsedQuery q = parser.makeSQL(dialect);
	//writeln(parser.whereClause.dump(0));
	//writeln(q.hql ~ "\n=>\n" ~ q.sql);

	//writeln(q.hql);
	//writeln(q.sql);
    parser = new QueryParser(schema, "SELECT a FROM Person AS a LEFT JOIN a.moreInfo as b LEFT JOIN b.evenMore c WHERE a.id = :Id AND b.flags > 0 AND c.flags > 0");
    assert(parser.fromClause.hasAlias("a"));
    assert(parser.fromClause.hasAlias("b"));
    assert(parser.fromClause.findByAlias("a").entityName == "Person");
    assert(parser.fromClause.findByAlias("b").entityName == "MoreInfo");
    assert(parser.fromClause.findByAlias("b").joinType == JoinType.LeftJoin);
    assert(parser.fromClause.findByAlias("c").entityName == "EvenMoreInfo");
    // indirect JOIN
    parser = new QueryParser(schema, "SELECT a FROM Person a WHERE a.id = :Id AND a.moreInfo.evenMore.flags > 0");
    assert(parser.fromClause.hasAlias("a"));
    assert(parser.fromClause.length == 3);
    assert(parser.fromClause[0].entity.tableName == "person");
    assert(parser.fromClause[1].entity.tableName == "person_info");
    assert(parser.fromClause[1].joinType == JoinType.InnerJoin);
    assert(parser.fromClause[1].pathString == "a.moreInfo");
    assert(parser.fromClause[2].entity.tableName == "person_info2");
    assert(parser.fromClause[2].joinType == JoinType.LeftJoin);
    assert(parser.fromClause[2].pathString == "a.moreInfo.evenMore");
    // indirect JOIN, no alias
    parser = new QueryParser(schema, "FROM Person WHERE id = :Id AND moreInfo.evenMore.flags > 0");
    assert(parser.fromClause.length == 3);
    assert(parser.fromClause[0].entity.tableName == "person");
    assert(parser.fromClause[0].fetch == true);
    //writeln("select fields [" ~ to!string(parser.fromClause[0].startColumn) ~ ", " ~ to!string(parser.fromClause[0].selectedColumns) ~ "]");
    //writeln("select fields [" ~ to!string(parser.fromClause[1].startColumn) ~ ", " ~ to!string(parser.fromClause[1].selectedColumns) ~ "]");
    //writeln("select fields [" ~ to!string(parser.fromClause[2].startColumn) ~ ", " ~ to!string(parser.fromClause[2].selectedColumns) ~ "]");
    assert(parser.fromClause[0].selectedColumns == 4);
    assert(parser.fromClause[1].entity.tableName == "person_info");
    assert(parser.fromClause[1].joinType == JoinType.InnerJoin);
    assert(parser.fromClause[1].pathString == "_a1.moreInfo");
    assert(parser.fromClause[1].fetch == true);
    assert(parser.fromClause[1].selectedColumns == 2);
    assert(parser.fromClause[2].entity.tableName == "person_info2");
    assert(parser.fromClause[2].joinType == JoinType.LeftJoin);
    assert(parser.fromClause[2].pathString == "_a1.moreInfo.evenMore");
    assert(parser.fromClause[2].fetch == true);
    assert(parser.fromClause[2].selectedColumns == 3);

    q = parser.makeSQL(dialect);
    //writeln(q.hql);
    //writeln(q.sql);

    parser = new QueryParser(schema, "FROM User WHERE id in (1, 2, (3 - 1 * 25) / 2, 4 + :Id, 5)");
    //writeln(parser.whereClause.dump(0));
    q = parser.makeSQL(dialect);
    //writeln(q.hql);
    //writeln(q.sql);

    parser = new QueryParser(schema, "FROM Customer WHERE users.id = 1");
    q = parser.makeSQL(dialect);
//    writeln(q.hql);
//    writeln(q.sql);
    assert(q.sql == "SELECT _t1.id, _t1.name, _t1.zip, _t1.city, _t1.street_address, _t1.account_type_fk FROM customers AS _t1 LEFT JOIN users AS _t2 ON _t1.id=_t2.customer_fk WHERE _t2.id = 1");

    parser = new QueryParser(schema, "FROM Customer WHERE id = 1");
    q = parser.makeSQL(dialect);
//    writeln(q.hql);
//    writeln(q.sql);
    assert(q.sql == "SELECT _t1.id, _t1.name, _t1.zip, _t1.city, _t1.street_address, _t1.account_type_fk FROM customers AS _t1 WHERE _t1.id = 1");

    parser = new QueryParser(schema, "FROM User WHERE roles.id = 1");
    q = parser.makeSQL(dialect);
    //writeln(q.hql);
    //writeln(q.sql);
    assert(q.sql == "SELECT _t1.id, _t1.name, _t1.flags, _t1.comment, _t1.customer_fk FROM users AS _t1 LEFT JOIN role_users AS _t1_t2 ON _t1.id=_t1_t2.user_fk LEFT JOIN role AS _t2 ON _t1_t2.role_fk=_t2.id WHERE _t2.id = 1");

    parser = new QueryParser(schema, "FROM Role WHERE users.id = 1");
    q = parser.makeSQL(dialect);
//    writeln(q.hql);
//    writeln(q.sql);
    assert(q.sql == "SELECT _t1.id, _t1.name FROM role AS _t1 LEFT JOIN role_users AS _t1_t2 ON _t1.id=_t1_t2.role_fk LEFT JOIN users AS _t2 ON _t1_t2.user_fk=_t2.id WHERE _t2.id = 1");
    
    parser = new QueryParser(schema, "FROM User WHERE customer.id = 1");
    q = parser.makeSQL(dialect);
//    writeln(q.hql);
//    writeln(q.sql);
    assert(q.sql == "SELECT _t1.id, _t1.name, _t1.flags, _t1.comment, _t1.customer_fk FROM users AS _t1 LEFT JOIN customers AS _t2 ON _t1.customer_fk=_t2.id WHERE _t2.id = 1");

    parser = new QueryParser(schema, "SELECT a2 FROM User AS a1 JOIN a1.roles AS a2 WHERE a1.id = 1");
    q = parser.makeSQL(dialect);
    //writeln(q.hql);
    //writeln(q.sql);
    assert(q.sql == "SELECT _t2.id, _t2.name FROM users AS _t1 INNER JOIN role_users AS _t1_t2 ON _t1.id=_t1_t2.user_fk INNER JOIN role AS _t2 ON _t1_t2.role_fk=_t2.id WHERE _t1.id = 1");

    parser = new QueryParser(schema, "SELECT a2 FROM Customer AS a1 JOIN a1.users AS a2 WHERE a1.id = 1");
    q = parser.makeSQL(dialect);
    //writeln(q.hql);
    //writeln(q.sql);
    assert(q.sql == "SELECT _t2.id, _t2.name, _t2.flags, _t2.comment, _t2.customer_fk FROM customers AS _t1 INNER JOIN users AS _t2 ON _t1.id=_t2.customer_fk WHERE _t1.id = 1");
    
}
