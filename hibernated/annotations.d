/**
 * Hibernate-like ORM for D language. Annotations.
 *
 */
module hibernated.annotations;

struct Entity {
	immutable string name;
	this(string name) { this.name = name; }
}

struct Table {
	immutable string name;
	this(string name) { this.name = name; }
}

struct Column {
	immutable string name;
	immutable int length;
	immutable bool nullable;
	immutable bool unique;
	this(string name) { this.name = name; }
	this(string name, int length) { this.name = name; this.length = length; }
	this(string name, int length, bool nullable) { this.name = name; this.length = length; this.nullable = nullable; }
	this(string name, bool nullable) { this.name = name; this.nullable = nullable; }
	this(string name, int length, bool nullable, bool unique) { this.name = name; this.length = length; this.nullable = nullable; this.unique = unique; }
	this(string name, bool nullable, bool unique) { this.name = name; this.nullable = nullable; this.unique = unique; }
}

struct JoinColumn {
	immutable string name;
	this(string name) { this.name = name; }
}

struct DynamicInsert {
	immutable bool enabled;
	this(bool enabled) { this.enabled = enabled; }
}

struct DynamicUpdate {
	immutable bool enabled;
	this(bool enabled) { this.enabled = enabled; }
}

// column is primary key
enum Id;

// column is server generated value (e.g. AUTO INCREMENT field)
enum Generated;


unittest {

	@Entity
	@Table("user")
	class User {

		@Id @Generated
		@Column("id")
		int id;

		@Column("name")
		string name;
	}
}
