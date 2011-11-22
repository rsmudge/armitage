package msf;

import java.io.*;
import java.net.*;
import java.text.*;
import java.util.*;
import javax.xml.*;
import javax.xml.parsers.*;
import javax.xml.transform.*;
import javax.xml.transform.dom.*;
import javax.xml.transform.stream.*;
import org.w3c.dom.*;

/* A self-expiring cache for RPC calls */
public class RpcCacheImpl {
	protected RpcConnection connection = null;
	protected Map cache = new HashMap();
	protected Map filters = new HashMap();

	private static class CacheEntry {
		public long last = 0L;
		public long wait = 2000L;
		public Object response = null;

		public boolean isExpired() {
			return (System.currentTimeMillis() - last) > wait;
		}

		public void touch(String method, long executeTime) {
			/* throttle the next call if this takes too long to execute */
			if (executeTime > 500) {
				wait = executeTime * 10;
				System.err.println("* " + method + " took " + executeTime + "ms - throttling next call");
			}
			else {
				wait = 2000L;
			}

			last = System.currentTimeMillis();
		}
	}

	public RpcCacheImpl(RpcConnection connection) {
		this.connection = connection;
	}

	public void setFilter(String user, Object[] filter) {
		synchronized (this) {
			Map temp = (Map)filter[0];
			if (temp.size() == 0) {
				System.err.println("Removed: " + user);
				filters.remove(user);
			}
			else {
				filters.put(user, filter);
			}
		}
	}

	public Object execute(String user, String methodName) throws IOException {
		return execute(methodName, null);
	}

	public Object execute(String user, String methodName, Object[] params) throws IOException {
		synchronized (this) {
			/* user has a dynamic workspace... let's work with that. */
			if (!methodName.equals("session.list") && filters.containsKey(user)) {
				long start = System.currentTimeMillis();
				Object[] filter = (Object[])filters.get(user);
				connection.execute("db.filter", filter);

				Object response;
				if (params == null) {
					response = connection.execute(methodName);
				}
				else {
					response = connection.execute(methodName, params);
				}
				connection.execute("db.filter", new Object[] { new HashMap() });
				long stop = System.currentTimeMillis() - start;
				System.err.println("Called user specific filter: " + user + ", " + methodName + ", " + stop + "ms");
				return response;
			}

			CacheEntry entry = null;

			if (cache.containsKey(methodName)) {
				entry = (CacheEntry)cache.get(methodName);
				if (!entry.isExpired()) {
					return entry.response;
				}
			}
			else {
				entry = new CacheEntry();
				cache.put(methodName, entry);
			}

			long time = System.currentTimeMillis();
			if (params == null) {
				entry.response = connection.execute(methodName);
			}
			else {
				entry.response = connection.execute(methodName, params);
			}
			time = System.currentTimeMillis() - time;
			entry.touch(methodName, time);

			return entry.response;
		}
	}
}
