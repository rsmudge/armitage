package msf;

import java.io.*;
import java.util.*;

public class RpcAsync implements RpcConnection, Async, Runnable {
	protected RpcQueue queue;
	protected RpcConnection connection;
	protected boolean connected = true;
	protected long    last = 0;

	public boolean isConnected() {
		return connected;
	}

	/* if we've talked in the last 10s, assume that we're OK */
	public boolean isResponsive() {
		return (System.currentTimeMillis() - last) < 10000;
	}

	public RpcAsync(RpcConnection connection) {
		this.connection = connection;
		new Thread(this).start();
	}

	public void disconnect() {
		connected = false;
	}

	public void execute_async(String methodName) {
		execute_async(methodName, new Object[]{}, null);
	}

	public void execute_async(String methodName, Object[] args) {
		execute_async(methodName, args, null);
	}

	public void execute_async(String methodName, Object[] args, RpcCallback callback) {
		if (queue == null) {
			queue = new RpcQueue(connection);
		}
		queue.execute(methodName, args, callback);
	}

	public Object execute(String methodName) throws IOException {
		last = System.currentTimeMillis();
		return connection.execute(methodName);
	}

	protected Map cache = new HashMap();

	/* issue a keep-alive every 1-2 minutes, if we're idle */
	public void run() {
		try {
			while (isConnected()) {
				Thread.sleep((60 * 1000) + (int)(Math.random() * 60 * 1000));
				if (!isResponsive()) {
					execute_async("core.version", new Object[0]);
				}
			}
		}
		catch (InterruptedException ie) {
			ie.printStackTrace();
		}
	}

	public Object execute(String methodName, Object[] params) throws IOException {
		if (methodName.equals("module.info") || methodName.equals("module.options") || methodName.equals("module.compatible_payloads")) {
			StringBuilder keysb = new StringBuilder(methodName);

			for(int i = 0; i < params.length; i++)
				keysb.append(params[i].toString());

			String key = keysb.toString();
			Object result = cache.get(key);

			if(result != null) {
				return result;
			}

			last = System.currentTimeMillis();
			result = connection.execute(methodName, params);
			cache.put(key, result);
			return result;
		}
		else {
			last = System.currentTimeMillis();
			return connection.execute(methodName, params);
		}
	}
}
