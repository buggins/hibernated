module hibernated.core;

import hibernated.annotations;
import hibernated.metadata;
import hibernated.type;

class HibernatedException : Exception {
    this(string msg, string f = __FILE__, size_t l = __LINE__) { super(msg, f, l); }
    this(Exception causedBy, string f = __FILE__, size_t l = __LINE__) { super(causedBy.msg, f, l); }
}

