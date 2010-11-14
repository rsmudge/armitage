package armitage;

import console.Console;
import msf.*;
import java.util.*;

/** A generic class to execute several queries and return their results */
public class ArmitageTimer implements Runnable {
	protected RpcConnection       connection;
	protected String              command;
	protected Object[]            arguments;
	protected long                sleepPeriod;
	protected ArmitageTimerClient client;

	public ArmitageTimer(RpcConnection connection, String command, Object[] arguments, long sleepPeriod, ArmitageTimerClient client) {
		this.connection  = connection;
		this.command     = command;
		this.arguments   = arguments;
		this.sleepPeriod = sleepPeriod;
		this.client      = client;
		new Thread(this).start();
	}

	private Map readFromClient() throws java.io.IOException {
		if (arguments == null) {
			return (Map)(connection.execute(command));
		}
		else {
			return (Map)(connection.execute(command, arguments));
		}
	}

	public void run() {
		Map read = null;

		try {
			while ((read = readFromClient()) != null) {
				if (client.result(command, arguments, read) == false) {
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
