module hibernated.metadata;

interface ClassMetadata {
	immutable string getEntityName();
	immutable TypeInfo getMappedClass();
	immutable string[] getPropertyNames();
}

string GenerateFieldList(T)() {
	string res = "";
	pragma(msg, "Generating field list");
	pragma(msg, T.tupleof);
	pragma(msg, "Attributes");
	pragma(msg, __traits(getAttributes, T));
	foreach(a; __traits(getAttributes, T)) {
		pragma(msg, a);
	}
//	alias typeof(__traits(allMembers, T)) mm;
//	pragma(msg, mm);
	foreach(m; __traits(allMembers, T)) {
		pragma(msg, m);
		//pragma(msg,typeid(m));
		pragma(msg,typeof(m));
		static if (is (FunctionTypeOf!(__traits(isVirtualFunction, m)) == function)) {
			pragma(msg,"Virtual function");
		}
		//TypeInfo * member = typeof(__traits(getMember, T, m));
		
//		auto mm = [__traits(getAttributes, typeid(typeof(m)))];
//		foreach (aa; mm) {
//			
//		}
//		pragma(msg, mm[0]);
//		foreach(aa; mm) {
//			pragma(msg, aa);
//		}
	}
//	foreach(i, ii; T.tupleof) {
//		res ~= __traits(identifier, T.tupleof[i]) ~ " ";
//		//pragma(msg, __traits(identifier, T.tupleof[i]));
//		//immutable string fieldName = __traits(identifier, T.tupleof[i]);
//		//immutable TypeInfo typeInfo = typeof(T.tupleof[i]);
//		//immutable auto attrs = __traits(getAttributes, T.tupleof[i]);
//		//pragma(msg, fieldName);
//		//pragma(msg, typeInfo);
//		//pragma(msg, attrs);
////		foreach (j, jj; __traits(getAttributes, T.tupleof[i])) {
////			pragma(msg, typeof(jj));
////		}
//	}
	return res;
}

class MetadataInfo(T) {
	string name;
	static string fields = GenerateFieldList!(T);
}

unittest {

	@Entity
	@Table("user")
	class User {

		@Id @Generated
		@Column("id")
		int id;

		@Column("name")
		string name;
		
		mixin GenerateEntityMetadata!();
		pragma(msg, "User entity fields: " ~ fields);
	}
}
