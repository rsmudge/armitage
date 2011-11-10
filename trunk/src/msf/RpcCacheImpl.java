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

	private static class CacheEntry {
		public long last = 0L;
		public long wait = 2000L;
		public Object response = null;

		public boolean isExpired() {
			return (System.currentTimeMillis() - last) > wait;
		}

		public void touch(String methodName, long executeTime) {
			if (executeTime > 1000L) {
				wait = executeTime * 5;
				System.err.println("Throttling wait time for: " + methodName + " (execute time: " + executeTime + ")");
			}

			last = System.currentTimeMillis();
		}
	}

	public RpcCacheImpl(RpcConnection connection) {
		this.connection = connection;
	}

	public Object execute(String methodName) throws IOException {
		return execute(methodName, null);
	}

	public Object execute(String methodName, Object[] params) throws IOException {
		synchronized (this) {
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
