module hibernated.session;

class HibernatedException : Exception {
	this(string msg) {
		super(msg);
	}
}

interface ConnectionFactory {
	Connection * getConnection();
}

interface Connection {
}

interface Transaction {
}

// similar to org.hibernate.Session
interface Session
{
	Transaction * beginTransaction();
	void cancelQuery();
	void clear();
	Connection * close();
	bool contains(Object * object);
	// renamed from Session.delete
	SessionFactory * getSessionFactory();
	string getEntityName(Object object);

	Object get(string entityName, Object id);
	Object load(string entityName, Object id);
	void refresh(Object obj);
	Object save(Object obj);
	string update(Object object);
	void remove(Object * object);

}

interface SessionFactory {
	void close();
	bool isClosed();
	Session * openSession();
}