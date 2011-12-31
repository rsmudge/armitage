package armitage;

import console.Console;
import msf.*;
import java.util.*;

/** A generic class to execute several queries and return their results */
public class ArmitageTimer implements Runnable {
	protected RpcConnection       connection;
	protected String              command;
	protected long                sleepPeriod;
	protected ArmitageTimerClient client;
	protected boolean             cacheProtocol;

	/* keep track of the last response we got *and* its hashcode... */
	protected Map                 lastRead = new HashMap();
	protected long                lastCode = 0L;

	public ArmitageTimer(RpcConnection connection, String command, long sleepPeriod, ArmitageTimerClient client, boolean doCache) {
		this.connection  = connection;
		this.command     = command;
		this.sleepPeriod = sleepPeriod;
		this.client      = client;
		cacheProtocol    = doCache;
		new Thread(this).start();
	}

	public static long dataIdentity(Object v) {
		long r = 0L;

		if (v == null) {
			return r;
		}
		else if (v instanceof Collection) {
			Iterator j = ((Collection)v).iterator();
			while (j.hasNext()) {
				r ^= dataIdentity(j.next());
			}
		}
		else if (v instanceof Map) {
			Iterator i = ((Map)v).values().iterator();
			while (i.hasNext()) {
				r ^= dataIdentity(i.next());
			}
		}
		else if (v instanceof Number) {
			r ^= v.hashCode();
		}
		else {
			r ^= v.toString().hashCode();
		}
		return r;
	}

	private Map readFromClient() throws java.io.IOException {
		Object arguments[];
		if (cacheProtocol) {
			arguments = new Object[1];
			arguments[0] = new Long(lastCode);
		}
		else {
			arguments = new Object[0];
		}

		Map result = (Map)connection.execute(command, arguments);

		if (!result.containsKey("nochange")) {
			lastRead = result;
			lastCode = dataIdentity(result);
		}

		return lastRead;
	}

	public void run() {
		Map read = null;

		try {
			while ((read = readFromClient()) != null) {
				if (client.result(command, null, read) == false) {
					return;
				}

				if (sleepPeriod <= 0) {
					return;
				}
				else {
					Thread.sleep(sleepPeriod);
				}
			}
		}
		catch (Exception javaSucksBecauseItMakesMeCatchEverythingFuckingThing) {
			System.err.println("Thread id: " + command + " -> " + read);
			javaSucksBecauseItMakesMeCatchEverythingFuckingThing.printStackTrace();
		}
	}
}
