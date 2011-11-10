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

/**
 * This is a modification of msfgui/RpcConnection.java by scriptjunkie. Taken from 
 * the Metasploit Framework Java GUI. 
 */
public abstract class RpcConnectionImpl implements RpcConnection {
	protected String rpcToken;
	private Map callCache = new HashMap();
	protected RpcConnection database = null;

	public void setDatabase(RpcConnection connection) {
		database = connection;
	}

	public RpcConnectionImpl() {
		/* empty */
	}

	/** Constructor sets up a connection and authenticates. */
	public RpcConnectionImpl(String username, String password, String host, int port, boolean secure, boolean debugf) {
	}

	/** Destructor cleans up. */
	protected void finalize() throws Throwable {
		super.finalize();
	}

	/** Method that sends a call to the server and received a response; only allows one at a time */
	protected Map exec (String methname, Object[] params) {
		try {
			synchronized(this) {
				writeCall(methname, params);
				Object response = readResp();
				if (response instanceof Map) {
					return (Map)response;
				}
				else {
					Map temp = new HashMap();
					temp.put("response", response);
					return temp;
				}
			}
		} 
		catch (RuntimeException rex) { 
			throw rex;
		}
		catch (Exception ex) { 
			throw new RuntimeException(ex);
		}
	}

	/** Runs command with no args */
	public Object execute(String methodName) throws IOException {
		return execute(methodName, new Object[]{});
	}

	/** Adds token, runs command, and notifies logger on call and return */
	public Object execute(String methodName, Object[] params) throws IOException {
		if (database != null && "db.".equals(methodName.substring(0, 3))) {
			return database.execute(methodName, params);
		}
		else {
			Object[] paramsNew = new Object[params.length+1];
			paramsNew[0] = rpcToken;
			System.arraycopy(params, 0, paramsNew, 1, params.length);
			Object result = cacheExecute(methodName, paramsNew);
			return result;
		}
	}

	/** Caches certain calls and checks cache for re-executing them.
	 * If not cached or not cacheable, calls exec. */
	private Object cacheExecute(String methodName, Object[] params) throws IOException {
		if (methodName.equals("module.info") || methodName.equals("module.options") || methodName.equals("module.compatible_payloads")) {
			StringBuilder keysb = new StringBuilder(methodName);

			for(int i = 1; i < params.length; i++)
				keysb.append(params[i].toString());

			String key = keysb.toString();
			Object result = callCache.get(key);

			if(result != null)
				return result;

			result = exec(methodName, params);
			callCache.put(key, result);
			return result;
		}
		return exec(methodName, params);
	}

	protected abstract void writeCall(String methodName, Object[] args) throws Exception;
	protected abstract Object readResp() throws Exception;
}
