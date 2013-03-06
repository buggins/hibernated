module hibernated.type;

interface Type {
	immutable string getName();
	immutable TypeInfo getReturnedClass();
}

class StringType : Type {
	immutable string getName() { return "String"; }
	immutable TypeInfo getReturnedClass() { return typeid(string); }

}

class IntegerType : Type {
	immutable string getName() { return ""; }
	immutable TypeInfo getReturnedClass() { return typeid(int); }

}

