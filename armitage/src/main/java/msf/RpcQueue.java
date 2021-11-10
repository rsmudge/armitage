package msf;

import console.*;

import java.util.*;
import java.awt.*;
import java.awt.event.*;

import msf.*;
import java.math.*;
import java.security.*;

/* A pretty quick and dirty queue for executing RPC commands in turn and discarding their output. This
   has to be 100x better than creating a thread for every async thing I want to have happen via an RPC
   call */
public class RpcQueue implements Runnable {
	protected RpcConnection connection;
	protected LinkedList    requests  = new LinkedList();

	private static class Request {
		public String      method;
		public Object[]    args;
		public RpcCallback callback = null;
	}

	public RpcQueue(RpcConnection connection) {
		this.connection = connection;
		new Thread(this).start();
	}

	protected void processRequest(Request r) {
		try {
			Object result = connection.execute(r.method, r.args);
			if (r.callback != null) {
				r.callback.result(result);
			}
		}
		catch (Exception ex) {
			armitage.ArmitageMain.print_error("RpcQueue Method '" + r.method + "' failed: " + ex.getMessage());
			for (int x = 0; x < r.args.length; x++) {
				System.err.println("\t" + x + ": " + r.args[x]);
			}
			ex.printStackTrace();

			/* let the user know something went wrong */
			if (r.callback != null) {
				Map result = new HashMap();
				result.put("error", ex.getMessage());
				r.callback.result((Object)result);
			}
		}
	}

	public void execute(String method, Object[] args) {
		execute(method, args, null);
	}

	public void execute(String method, Object[] args, RpcCallback callback) {
		synchronized (this) {
			Request temp  = new Request();
			temp.method   = method;
			if (args == null)
				temp.args = new Object[0];
			else
				temp.args = args;
			temp.callback = callback;
			requests.add(temp);
		}
	}

	protected Request grabRequest() {
		synchronized (this) {
			return (Request)requests.pollFirst();
		}
	}

	/* keep grabbing requests */
	public void run() {
		try {
			while (true) {
				Request next = grabRequest();
				if (next != null) {
					processRequest(next);
					Thread.yield();
				}
				else {
					Thread.sleep(50);
				}
			}
		}
		catch (Exception ex) {
			ex.printStackTrace();
			return;
		}
	}
}
